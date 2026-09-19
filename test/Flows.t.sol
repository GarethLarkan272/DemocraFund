// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "./TestBase.sol";
import {ProjectEscrow} from "../src/ProjectEscrow.sol";
import {ProjectGovernance} from "../src/ProjectGovernance.sol";
import {Redemption} from "../src/Redemption.sol";

/// @title FlowTest
/// @notice End-to-end journeys through the whole stack: company registration
///         -> tender -> bid -> vote -> award -> (VRF) committee -> milestone
///         releases -> completion -> redemption. Also the cancellation,
///         deposit, multi-company and expiry journeys.
contract FlowTest is TestBase {
    /// The full happy path, VRF included: 4 opt-ins trigger a real draw,
    /// all milestones release, the project completes, and the builder
    /// off-ramps through the redemption receipt.
    function testFullHappyPathEndToEndWithVRF() public {
        escrow = _deployAndAward(4);
        assertTrue(governance.selectionPending());

        uint256[] memory words = new uint256[](4); // pool 4 -> numWords 4
        words[0] = 1;
        words[1] = 2;
        words[2] = 3;
        words[3] = 0;
        _fulfill(words);
        assertTrue(escrow.committeeFinalized());

        for (uint256 m; m < 3; m++) {
            bytes32 evidence = keccak256(abi.encode("stage", m));
            vm.prank(builder);
            escrow.submitMilestoneComplete(evidence);
            // Drawn committee: memberAddrs[1], [2], [3] (words 1..3).
            escrow.approveMilestone(_milestoneSigs(m, evidence, toUint256Array(ADMIN_PK, 101)));
        }
        assertTrue(escrow.allMilestonesReleased());

        // Completion sweeps the un-owed fee reserve (reserve 90, only member
        // 101 signed: 30 accrued) to the treasury.
        governance.completeProject();
        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.COMPLETE));
        assertEq(escrow.totalSweptToTreasury(), escrow.feeReserve() - escrow.totalUncollectedFees());

        // The signing member collects their accrued fee.
        vm.prank(memberAddrs[1]);
        escrow.collectFees();
        assertEq(token.balanceOf(memberAddrs[1]), 3 * COMMITTEE_FEE);

        // Builder off-ramps everything earned.
        vm.prank(builder);
        token.approve(address(redemption), COST);
        vm.prank(builder);
        uint256 tokenId = redemption.redeem(COST, keccak256("builder bank"), address(escrow));
        redemption.markPaid(tokenId, "EFT-8821");

        (,,,, Redemption.ReceiptState state, string memory payoutRef) = redemption.receipts(tokenId);
        assertEq(uint8(state), uint8(Redemption.ReceiptState.Paid));
        assertEq(payoutRef, "EFT-8821");
        assertEq(token.balanceOf(builder), 0);
    }

    /// The cancellation journey: award, one release, 4-of-5 cancellation,
    /// treasury refund, lifecycle finalised, remaining funds redeemed.
    function testCancellationFlowEndToEnd() public {
        escrow = _deployAndAward(3);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100)));
        assertEq(escrow.totalReleased(), AMOUNTS[0]);

        bytes32 reason = keccak256("builder abandoned site mid-project");
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(100, 101, 102, ADMIN_PK)));
        assertTrue(escrow.cancelled());
        // The refund keeps member 100's uncollected fee in the escrow.
        assertEq(token.balanceOf(treasury), COST + escrow.feeReserve() - AMOUNTS[0] - COMMITTEE_FEE);
        assertEq(escrow.totalUncollectedFees(), COMMITTEE_FEE);

        governance.cancelProject();
        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.CANCELLED));

        // The signing member still collects their fee after cancellation.
        vm.prank(memberAddrs[0]);
        escrow.collectFees();
        assertEq(token.balanceOf(memberAddrs[0]), COMMITTEE_FEE);

        // The builder off-ramps what they legitimately earned.
        vm.prank(builder);
        token.approve(address(redemption), AMOUNTS[0]);
        vm.prank(builder);
        uint256 tokenId = redemption.redeem(AMOUNTS[0], keccak256("builder bank"), address(escrow));
        redemption.markPaid(tokenId, "EFT-5544");

        (,,,, Redemption.ReceiptState state,) = redemption.receipts(tokenId);
        assertEq(uint8(state), uint8(Redemption.ReceiptState.Paid));
    }

    /// Deposit journey: the first milestone auto-releases at award, the rest
    /// follow the normal approval loop.
    function testDepositFlowEndToEnd() public {
        _deployProject();
        for (uint256 i; i < 3; i++) {
            vm.prank(memberAddrs[i]);
            governance.optInForCommittee();
        }

        vm.prank(builder);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, true, _proposalMilestones());

        vm.warp(block.timestamp + 9 days);
        vm.prank(admin);
        governance.closeProposalsAndOpenVoting();
        vm.prank(memberAddrs[0]);
        governance.voteForProposal(0);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        governance.closeVoting(5);
        vm.prank(admin);
        governance.awardProposal(0);

        escrow = ProjectEscrow(governance.projectEscrow());
        assertEq(escrow.totalReleased(), AMOUNTS[0]); // deposit released at award
        assertEq(escrow.currentMilestoneIndex(), 1);
        assertEq(token.balanceOf(builder), AMOUNTS[0]);

        // Remaining milestones through the normal loop.
        for (uint256 m = 1; m < 3; m++) {
            bytes32 evidence = keccak256(abi.encode("stage", m));
            vm.prank(builder);
            escrow.submitMilestoneComplete(evidence);
            escrow.approveMilestone(_milestoneSigs(m, evidence, toUint256Array(ADMIN_PK, 100)));
        }
        assertTrue(escrow.allMilestonesReleased());
        assertEq(token.balanceOf(builder), COST);
    }

    /// Multi-company tender: two bids, votes split, shortlist enforced, the
    /// winner awarded and executed.
    function testMultiCompanyFlowEndToEnd() public {
        vm.prank(memberAddrs[1]);
        registry.registerCompany(memberAddrs[1], keccak256("second company"));
        _deployProject();

        // 3 opt-ins so the award produces a real committee.
        for (uint256 i; i < 3; i++) {
            vm.prank(memberAddrs[i]);
            governance.optInForCommittee();
        }

        vm.prank(builder);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());
        vm.prank(memberAddrs[1]);
        governance.createProposal(2, keccak256("s2"), keccak256("i2"), COST, false, _proposalMilestones());

        vm.warp(block.timestamp + 9 days);
        vm.prank(admin);
        governance.closeProposalsAndOpenVoting();

        // proposal 0 wins the vote 2-1.
        vm.prank(memberAddrs[0]);
        governance.voteForProposal(0);
        vm.prank(memberAddrs[2]);
        governance.voteForProposal(0);
        vm.prank(memberAddrs[3]);
        governance.voteForProposal(1);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        governance.closeVoting(1);

        vm.prank(admin);
        vm.expectRevert(ProjectGovernance.NotInShortlist.selector);
        governance.awardProposal(1);

        vm.prank(admin);
        governance.awardProposal(0);
        escrow = ProjectEscrow(governance.projectEscrow());

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100)));
        assertEq(escrow.totalReleased(), AMOUNTS[0]);
        assertEq(escrow.projectWallet(), builder); // company 1's payment wallet
    }

    /// The expiry journey: deliberation expires, anyone cancels, nothing was
    /// ever funded.
    function testExpiryFlowEndToEnd() public {
        _deployProject();
        vm.prank(builder);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());

        vm.warp(block.timestamp + 9 days);
        vm.prank(admin);
        governance.closeProposalsAndOpenVoting();
        vm.prank(memberAddrs[0]);
        governance.voteForProposal(0);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        governance.closeVoting(5);

        vm.warp(block.timestamp + 8 days); // award window elapsed
        governance.expireDeliberation();

        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.CANCELLED));
        assertEq(uint8(governance.cancelledForm()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.DELIBERATION));
        assertEq(address(governance.projectEscrow()), address(0));
        assertEq(token.totalSupply(), 0);

        // Nothing can be voted or awarded anymore.
        vm.prank(memberAddrs[1]);
        vm.expectRevert(ProjectGovernance.InvalidProjectLifecycle.selector);
        governance.voteForProposal(0);
    }
}
