// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "./TestBase.sol";
import {ProjectGovernance} from "../src/ProjectGovernance.sol";
import {ProjectFactory} from "../src/ProjectFactory.sol";
import {ProjectEscrow} from "../src/ProjectEscrow.sol";
import {IProjectConfig} from "../src/Interfaces/IProjectConfig.sol";

/// @title GovernanceTest
/// @notice Governance-layer unit tests: vote-bound shortlist enforcement,
///         award deadlines and expiry, permissionless VRF retry/abort
///         timeouts, one-proposal-per-company, active-company bidding, fee
///         cap and factory mint validation.
contract GovernanceTest is TestBase {
    // --------------------------------------------------------------------------
    // --------------------------- SHORTLIST & AWARD -----------------------------
    // --------------------------------------------------------------------------

    /// The award is bound to the votes: with a shortlist of 1, only the
    /// top-voted proposal can be awarded.
    function testAwardRequiresTopVotedWithShortlistOne() public {
        _deployProject();
        _twoCompanyBids();

        vm.warp(block.timestamp + 9 days);
        vm.prank(admin);
        governance.closeProposalsAndOpenVoting();

        // proposal 0 gets 2 votes, proposal 1 gets 1.
        vm.prank(memberAddrs[0]);
        governance.voteForProposal(0);
        vm.prank(memberAddrs[1]);
        governance.voteForProposal(0);
        vm.prank(memberAddrs[2]);
        governance.voteForProposal(1);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        governance.closeVoting(1);

        // Loser cannot be awarded.
        vm.prank(admin);
        vm.expectRevert(ProjectGovernance.NotInShortlist.selector);
        governance.awardProposal(1);

        // Winner can.
        vm.prank(admin);
        governance.awardProposal(0);
    }

    /// Boundary ties all pass: a shortlist of 1 with two tied leaders admits
    /// both.
    function testShortlistTiesAllPass() public {
        _deployProject();
        _twoCompanyBids();

        vm.warp(block.timestamp + 9 days);
        vm.prank(admin);
        governance.closeProposalsAndOpenVoting();

        // One vote each - tied for first.
        vm.prank(memberAddrs[0]);
        governance.voteForProposal(0);
        vm.prank(memberAddrs[1]);
        governance.voteForProposal(1);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        governance.closeVoting(1);

        vm.prank(admin);
        governance.awardProposal(1);
    }

    /// The award cannot happen after awardDeadline.
    function testAwardPastDeadlineReverts() public {
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

        vm.warp(block.timestamp + 8 days); // past the 7-day deliberation window
        vm.prank(admin);
        vm.expectRevert(ProjectGovernance.AwardDeadlinePassed.selector);
        governance.awardProposal(0);
    }

    /// After awardDeadline anyone can expire the tender - nothing was funded.
    function testExpireDeliberationPermissionless() public {
        _deployProject();

        vm.warp(block.timestamp + 9 days);
        vm.prank(admin);
        governance.closeProposalsAndOpenVoting();

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        governance.closeVoting(5);

        // Before the deadline, expiry reverts.
        vm.expectRevert(ProjectGovernance.VotingStillOpen.selector);
        governance.expireDeliberation();

        vm.warp(block.timestamp + 8 days);
        governance.expireDeliberation();

        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.CANCELLED));
        assertEq(address(governance.projectEscrow()), address(0));
        assertEq(token.totalSupply(), 0);
    }

    // --------------------------------------------------------------------------
    // ---------------------------- VRF TIMEOUT PATHS ----------------------------
    // --------------------------------------------------------------------------

    /// A pending draw can be retried by anyone after SELECTION_RETRY_DELAY.
    function testRetryPermissionlessAfterDelay() public {
        _deployAndAward(4);
        assertTrue(governance.selectionPending());

        // Admin may retry immediately.
        vm.prank(admin);
        governance.retryCommitteeSelection();

        // Others may not until the delay passes.
        vm.prank(outsider);
        vm.expectRevert();
        governance.retryCommitteeSelection();

        vm.warp(block.timestamp + 8 days);
        uint256 oldRequestId = governance.selectionRequestId();
        governance.retryCommitteeSelection();
        assertNotEq(governance.selectionRequestId(), oldRequestId);
        assertTrue(governance.selectionPending());
    }

    /// A stuck draw can be aborted by anyone after the delay - funds return
    /// to the treasury.
    function testAbortPermissionlessAfterDelay() public {
        escrow = _deployAndAward(4);
        assertTrue(governance.selectionPending());

        vm.prank(outsider);
        vm.expectRevert();
        governance.cancelProject();

        vm.warp(block.timestamp + 8 days);
        governance.cancelProject();

        assertTrue(escrow.cancelled());
        assertEq(token.balanceOf(treasury), COST + escrow.feeReserve());
        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.CANCELLED));
    }

    // --------------------------------------------------------------------------
    // ----------------------------- PROPOSAL RULES ------------------------------
    // --------------------------------------------------------------------------

    /// A company can only bid once per tender.
    function testOneProposalPerCompany() public {
        _deployProject();

        vm.prank(builder);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());

        vm.prank(builder);
        vm.expectRevert(ProjectGovernance.AlreadySubmittedProposal.selector);
        governance.createProposal(COMPANY_ID, keccak256("s2"), keccak256("i2"), COST, false, _proposalMilestones());
    }

    /// Deregistered companies cannot bid.
    function testInactiveCompanyCannotBid() public {
        vm.prank(builder);
        registry.setCompanyActive(false);

        _deployProject();
        vm.prank(builder);
        vm.expectRevert(ProjectGovernance.CompanyNotActive.selector);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());

        // Re-activating restores the right to bid.
        vm.prank(builder);
        registry.setCompanyActive(true);
        vm.prank(builder);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());
    }

    // --------------------------------------------------------------------------
    // ------------------------------ FACTORY GUARDS -----------------------------
    // --------------------------------------------------------------------------

    /// The committee fee is hard-capped by the factory.
    function testFeeCapEnforcedByFactory() public {
        IProjectConfig.ProjectConfig memory cfg = _projectConfig();
        cfg.committeeFeePerSignature = 1001;

        vm.prank(creator);
        vm.expectRevert(ProjectFactory.FeeTooHigh.selector);
        factory.createProject(cfg);
    }

    /// A zero deliberation window is rejected.
    function testDeliberationWindowMustBeNonZero() public {
        IProjectConfig.ProjectConfig memory cfg = _projectConfig();
        cfg.deliberationWindow = 0;

        vm.prank(creator);
        vm.expectRevert(ProjectFactory.InvalidDeliberationWindow.selector);
        factory.createProject(cfg);
    }

    /// mintInitialSupplyForProject only funds the caller's own escrow.
    function testMintRejectsForeignEscrow() public {
        _deployAndAward(0);
        ProjectEscrow foreign = _newEscrow();

        vm.prank(address(governance));
        vm.expectRevert(ProjectFactory.ProjectNonExistent.selector);
        factory.mintInitialSupplyForProject(address(foreign), COST);
    }

    /// mintInitialSupplyForProject cannot exceed the project's budget cap plus
    /// its fee reserve.
    function testMintRejectsOverBudgetCap() public {
        _deployAndAward(0);

        // Compute into a local: the view call would consume the cheatcodes.
        uint256 overCap = BUDGET_CAP + escrow.feeReserve() + 1;
        vm.prank(address(governance));
        vm.expectRevert(ProjectFactory.ZeroAmount.selector);
        factory.mintInitialSupplyForProject(address(escrow), overCap);
    }

    // --------------------------------------------------------------------------
    // ------------------------------ CANCELLATION -------------------------------
    // --------------------------------------------------------------------------

    /// Pre-award cancellation is admin-only.
    function testPreAwardCancelAdminOnly() public {
        _deployProject();

        vm.expectRevert();
        governance.cancelProject();

        vm.prank(admin);
        governance.cancelProject();
        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.CANCELLED));
        assertEq(uint8(governance.cancelledForm()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.PROPOSAL));
    }

    /// Once the escrow's 4-of-5 cancellation fired, anyone can finalise the
    /// lifecycle.
    function testCancelFinalisePermissionless() public {
        escrow = _deployAndAward(3);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100)));

        bytes32 reason = keccak256("abandoned");
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(100, 101, 102, ADMIN_PK)));
        assertTrue(escrow.cancelled());

        governance.cancelProject();
        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.CANCELLED));
    }

    // --------------------------------------------------------------------------
    // ------------------------- FACTORY & GOVERNANCE GUARDS ---------------------
    // --------------------------------------------------------------------------

    /// createProject rejects a zero treasury wallet up front.
    function testCreateProjectRejectsZeroTreasury() public {
        IProjectConfig.ProjectConfig memory cfg = _projectConfig();
        cfg.treasuryWallet = address(0);

        vm.prank(creator);
        vm.expectRevert(ProjectFactory.AddressZero.selector);
        factory.createProject(cfg);
    }

    /// The proposal window must respect the platform minimum.
    function testCreateProjectRejectsShortProposalWindow() public {
        IProjectConfig.ProjectConfig memory cfg = _projectConfig();
        cfg.proposalDeadline = uint64(block.timestamp + 1 days); // below the 1-week minimum

        vm.prank(creator);
        vm.expectRevert(ProjectFactory.InvalidProposalSubmissionDuration.selector);
        factory.createProject(cfg);
    }

    /// The factory constructor rejects zero addresses and a broken VRF
    /// configuration.
    function testFactoryConstructorValidation() public {
        IProjectConfig.VRFConfig memory vrfCfg = IProjectConfig.VRFConfig({
            coordinator: address(vrf),
            subscriptionId: subscriptionId,
            keyHash: bytes32(uint256(1)),
            callbackGasLimit: 500_000,
            requestConfirmations: 3,
            nativePayment: false
        });

        // Deploy the impl first: `new` consumes vm.expectRevert.
        ProjectEscrow impl = new ProjectEscrow();
        vm.expectRevert(ProjectFactory.AddressZero.selector);
        new ProjectFactory(1 weeks, 1 weeks, 1 weeks, address(0), address(impl), creator, address(registry), vrfCfg);

        IProjectConfig.VRFConfig memory brokenVrfCfg = vrfCfg;
        brokenVrfCfg.keyHash = bytes32(0);
        vm.expectRevert(ProjectFactory.InvalidVRFConfig.selector);
        new ProjectFactory(
            1 weeks, 1 weeks, 1 weeks, address(token), address(impl), creator, address(registry), brokenVrfCfg
        );
    }

    /// The global voting-duration floor is admin-only and cannot be zero.
    function testAdminUpdatesGlobalVotingDuration() public {
        factory.updateGlobalMinimumVotingDuration(2 weeks);
        assertEq(factory.globalMinimumVotingDuration(), 2 weeks);

        vm.expectRevert(ProjectFactory.ZeroAmount.selector);
        factory.updateGlobalMinimumVotingDuration(0);

        vm.prank(outsider);
        vm.expectRevert();
        factory.updateGlobalMinimumVotingDuration(1 weeks);
    }

    /// cancelProject is rejected once the lifecycle is terminal (CANCELLED
    /// or COMPLETE).
    function testCancelProjectAtTerminalLifecycleReverts() public {
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

        vm.expectRevert(ProjectGovernance.InvalidProjectLifecycle.selector);
        governance.cancelProject();
    }

    /// Post-award with a finalised committee, the escrow's own signature
    /// cancellation must fire first - the governance cannot cancel a live
    /// escrow.
    function testCancelProjectRequiresEscrowCancellation() public {
        escrow = _deployAndAward(3);
        assertTrue(escrow.committeeFinalized());

        vm.prank(admin);
        vm.expectRevert(ProjectGovernance.EscrowNotCancelled.selector);
        governance.cancelProject();
    }

    /// Proposals may not pre-declare milestones as released.
    function testCreateProposalRejectsReleasedMilestones() public {
        _deployProject();

        ProjectGovernance.Milestone[] memory bad = new ProjectGovernance.Milestone[](3);
        bad[0] = ProjectGovernance.Milestone(300, bytes32(0), true); // released!
        bad[1] = ProjectGovernance.Milestone(300, bytes32(0), false);
        bad[2] = ProjectGovernance.Milestone(400, bytes32(0), false);

        vm.prank(builder);
        vm.expectRevert(ProjectGovernance.MilestoneReleased.selector);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, bad);
    }

    /// One member, one vote: the second vote from the same wallet reverts.
    function testDoubleVoteReverts() public {
        _deployProject();
        vm.prank(builder);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());

        vm.warp(block.timestamp + 9 days);
        vm.prank(admin);
        governance.closeProposalsAndOpenVoting();

        vm.prank(memberAddrs[0]);
        governance.voteForProposal(0);

        vm.prank(memberAddrs[0]);
        vm.expectRevert(ProjectGovernance.UserAlreadyVoted.selector);
        governance.voteForProposal(0);
    }

    // --------------------------------------------------------------------------
    // ---------------------------------- HELPERS --------------------------------
    // --------------------------------------------------------------------------

    /// Creates two bids: company 1 (builder) and company 2 (memberAddrs[1]).
    function _twoCompanyBids() internal {
        vm.prank(memberAddrs[1]);
        registry.registerCompany(memberAddrs[1], keccak256("second company"));

        vm.prank(builder);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());
        vm.prank(memberAddrs[1]);
        governance.createProposal(2, keccak256("s2"), keccak256("i2"), COST, false, _proposalMilestones());
    }
}
