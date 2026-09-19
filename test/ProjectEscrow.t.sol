// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {ProjectFactory} from "../src/ProjectFactory.sol";
import {ProjectGovernance} from "../src/ProjectGovernance.sol";
import {ProjectEscrow} from "../src/ProjectEscrow.sol";
import {CompanyRegistry} from "../src/CompanyRegistry.sol";
import {Redemption} from "../src/Redemption.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";

import {TestBase, DummyGovernance, MockERC1271Wallet} from "./TestBase.sol";

/// @title ProjectEscrowTest
/// @notice Escrow release rules for every committee size (M = 0..3),
///         EIP-712 signature correctness, cancellation paths, committee
///         fees, redemption, and VRF committee selection against Chainlink's
///         official VRFCoordinatorV2_5Mock.
contract ProjectEscrowTest is TestBase {
    // --------------------------------------------------------------------------
    // --------------------------- MILESTONE RELEASE RULES -----------------------
    // --------------------------------------------------------------------------

    function testM0FallbackReleasesOnAdminAndBuilder() public {
        _newEscrow();
        _setMembers(new uint256[](0), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        // Builder alone: no release.
        assertEq(escrow.totalReleased(), 0);

        ProjectEscrow.Signature[] memory sigs = _milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK));
        escrow.approveMilestone(sigs);

        assertEq(escrow.totalReleased(), AMOUNTS[0]);
        assertEq(token.balanceOf(builder), AMOUNTS[0]);
        assertEq(escrow.currentMilestoneIndex(), 1);
    }

    function testM1RequiresEverySigner() public {
        _newEscrow();
        _setMembers(toUint256Array(100), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK)));
        assertEq(escrow.totalReleased(), 0);

        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(100)));
        assertEq(escrow.totalReleased(), AMOUNTS[0]);
    }

    function testM2AdminAndBuilderNeedOneMember() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        // Members without admin: no release.
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(100, 101)));
        assertEq(escrow.totalReleased(), 0);

        // Admin joins: release.
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK)));
        assertEq(escrow.totalReleased(), AMOUNTS[0]);
    }

    function testM3MembersCannotReleaseWithoutAdmin() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        // Builder + all 3 members, no admin: no release.
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(100, 101, 102)));
        assertEq(escrow.totalReleased(), 0);

        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK)));
        assertEq(escrow.totalReleased(), AMOUNTS[0]);
    }

    function testNoApprovalBeforeBuilderSubmits() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        ProjectEscrow.Signature[] memory sigs = _milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK));
        vm.expectRevert(ProjectEscrow.BuilderMustSubmitFirst.selector);
        escrow.approveMilestone(sigs);
    }

    function testEvidenceHashStoredIsBuilders() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100)));

        (, bytes32 storedEvidence,) = escrow.milestones(0);
        assertEq(storedEvidence, EVIDENCE);
    }

    function testNoApprovalBeforeCommitteeFinalized() public {
        _newEscrow();

        vm.prank(builder);
        vm.expectRevert(ProjectEscrow.CommitteeNotFinalized.selector);
        escrow.submitMilestoneComplete(EVIDENCE);
    }

    function testBuilderCannotApproveViaBatch() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        ProjectEscrow.Signature[] memory sigs = _milestoneSigs(0, EVIDENCE, toUint256Array(BUILDER_PK));
        vm.expectRevert(ProjectEscrow.BuilderMustSubmitDirectly.selector);
        escrow.approveMilestone(sigs);
    }

    function testInvalidSignatureReverts() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        // Sign the admin digest with the outsider's key.
        bytes32 digest = escrow.getMilestoneApprovalDigest(0, EVIDENCE, admin);
        ProjectEscrow.Signature[] memory sigs = new ProjectEscrow.Signature[](1);
        sigs[0] = ProjectEscrow.Signature({signer: admin, signature: _sign(OUTSIDER_PK, digest)});

        vm.expectRevert(ProjectEscrow.InvalidSignature.selector);
        escrow.approveMilestone(sigs);
    }

    function testSignatureCommittedToSpecificEvidence() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        // Signed against a different evidence hash than what was submitted.
        bytes32 wrongDigest = escrow.getMilestoneApprovalDigest(0, keccak256("other"), admin);
        ProjectEscrow.Signature[] memory sigs = new ProjectEscrow.Signature[](1);
        sigs[0] = ProjectEscrow.Signature({signer: admin, signature: _sign(ADMIN_PK, wrongDigest)});

        vm.expectRevert(ProjectEscrow.InvalidSignature.selector);
        escrow.approveMilestone(sigs);
    }

    function testSignatureReplayRejected() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        ProjectEscrow.Signature[] memory sigs = _milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK));
        escrow.approveMilestone(sigs);

        // The signature is already recorded for this milestone: replay rejected.
        vm.expectRevert(ProjectEscrow.AlreadySigned.selector);
        escrow.approveMilestone(sigs);
    }

    function testNonSignerCannotSubmitOrApprove() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(outsider);
        vm.expectRevert(ProjectEscrow.NotBuilder.selector);
        escrow.submitMilestoneComplete(EVIDENCE);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        ProjectEscrow.Signature[] memory sigs = new ProjectEscrow.Signature[](1);
        sigs[0] = ProjectEscrow.Signature({signer: outsider, signature: _sign(OUTSIDER_PK, bytes32(0))});

        vm.expectRevert(ProjectEscrow.NotSigner.selector);
        escrow.approveMilestone(sigs);
    }

    function testDuplicateMembersRejected() public {
        _newEscrow();
        vm.expectRevert(ProjectEscrow.DuplicateSigner.selector);
        _setMembers(toUint256Array(100, 100), new uint256[](0));
    }

    function testTooManyMembersRejected() public {
        _newEscrow();
        vm.expectRevert(ProjectEscrow.TooManyMembers.selector);
        _setMembers(toUint256Array(100, 101, 102, 103), new uint256[](0));
    }

    function testCommitteeFinalizedOnlyOnce() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.expectRevert(ProjectEscrow.CommitteeAlreadyFinalized.selector);
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));
    }

    /// Initialization rejects zero wallets up front.
    function testInitializeRejectsZeroAddresses() public {
        ProjectEscrow impl = new ProjectEscrow();
        address clone = Clones.clone(address(impl));
        escrow = ProjectEscrow(clone);

        vm.prank(gov);
        vm.expectRevert(ProjectEscrow.AddressZero.selector);
        escrow.initialize(builder, address(0), address(token), admin, builder, COST, _milestoneAmounts(), COMMITTEE_FEE);
    }

    /// The committee cannot be set once the escrow is cancelled (via the
    /// pre-finalization abort - a signature cancellation requires a
    /// committee, so it can never produce this state).
    function testSetCommitteeMembersOnCancelledProjectReverts() public {
        _newEscrow();

        vm.prank(gov);
        escrow.abort();
        assertTrue(escrow.cancelled());

        address[] memory members = new address[](1);
        members[0] = memberAddrs[0];
        vm.prank(gov);
        vm.expectRevert(ProjectEscrow.ProjectCancelled.selector);
        escrow.setCommitteeMembers(members, new address[](0));
    }

    /// The surplus sweep cannot run on a cancelled project (the refund
    /// already returned the un-owed money).
    function testSweepSurplusOnCancelledProjectReverts() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        bytes32 reason = keccak256("abandoned");
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(100, 101, 102, ADMIN_PK)));
        assertTrue(escrow.cancelled());

        vm.prank(gov);
        vm.expectRevert(ProjectEscrow.ProjectCancelled.selector);
        escrow.sweepSurplusToTreasury();
    }

    /// Cancellation signatures must commit to the exact reason hash being
    /// submitted - a signature over a different hash is rejected.
    function testCancellationBadSignatureReverts() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        bytes32 reason = keccak256("real reason");
        bytes32 wrongReason = keccak256("wrong reason");
        ProjectEscrow.Signature[] memory sigs = _cancellationSigs(wrongReason, toUint256Array(100));
        vm.expectRevert(ProjectEscrow.InvalidSignature.selector);
        escrow.approveCancellation(reason, sigs);
    }

    /// Promotion signatures must commit to the exact (alternate, member)
    /// pair being requested - a signature over different indices is rejected.
    function testPromotionBadSignatureReverts() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), toUint256Array(110));

        // Signed for (alternate 0, member 1) but requested as (0, 0).
        ProjectEscrow.Signature[] memory sigs = _promotionSigs(0, 1, toUint256Array(ADMIN_PK, BUILDER_PK, 100));
        vm.expectRevert(ProjectEscrow.InvalidSignature.selector);
        escrow.promoteAlternate(0, 0, sigs);
    }

    /// isSigner: admin, builder and committee members are signers; everyone
    /// else (including alternates) is not.
    function testIsSignerView() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), toUint256Array(110));

        assertTrue(escrow.isSigner(admin));
        assertTrue(escrow.isSigner(builder));
        assertTrue(escrow.isSigner(memberAddrs[0]));
        assertTrue(escrow.isSigner(memberAddrs[1]));
        assertTrue(escrow.isSigner(memberAddrs[2]));
        assertFalse(escrow.isSigner(outsider));
        assertFalse(escrow.isSigner(memberAddrs[10])); // alternate, not a signer
    }

    /// The EIP-712 domain separator is materialised per clone.
    function testDomainSeparatorView() public {
        _newEscrow();
        bytes32 firstDomain = escrow.domainSeparator();
        assertTrue(firstDomain != bytes32(0));

        _newEscrow();
        assertTrue(escrow.domainSeparator() != firstDomain); // per-address domain
    }

    function testFullProjectReleasesSequentially() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        for (uint256 m; m < 3; m++) {
            vm.prank(builder);
            escrow.submitMilestoneComplete(keccak256(abi.encode(EVIDENCE, m)));

            escrow.approveMilestone(
                _milestoneSigs(m, keccak256(abi.encode(EVIDENCE, m)), toUint256Array(ADMIN_PK, 100))
            );

            assertEq(escrow.currentMilestoneIndex(), m + 1);
        }

        assertEq(escrow.totalReleased(), COST);
        assertEq(token.balanceOf(builder), COST);
        assertTrue(escrow.allMilestonesReleased());
    }

    // --------------------------------------------------------------------------
    // -------------------------------- COMMITTEE FEES ---------------------------
    // --------------------------------------------------------------------------

    /// Signing members accrue the fee when the milestone releases; members who
    /// did not sign, the builder and the admin get nothing. Fees are credits
    /// in the escrow (pull-based), not minted at release.
    function testCommitteeFeesAccruedToSigningMembers() public {
        escrow = _deployAndAward(3);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100)));

        assertEq(escrow.totalReleased(), AMOUNTS[0]);
        assertEq(escrow.feeCredits(memberAddrs[0]), COMMITTEE_FEE);
        assertEq(escrow.feeCredits(memberAddrs[1]), 0);
        assertEq(escrow.feeCredits(memberAddrs[2]), 0);
        assertEq(escrow.totalUncollectedFees(), COMMITTEE_FEE);

        // The fee money was funded into the escrow at award (budget plus the
        // fee reserve): the builder's payout and the escrow's remaining
        // budget are untouched by the accrual.
        assertEq(token.balanceOf(address(escrow)), COST + escrow.feeReserve() - AMOUNTS[0]);
        assertEq(token.balanceOf(builder), AMOUNTS[0]);
    }

    /// Every member who signs a released milestone accrues the fee.
    function testCommitteeFeesAccruedToEverySigningMember() public {
        escrow = _deployAndAward(3);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100, 101)));

        assertEq(escrow.feeCredits(memberAddrs[0]), COMMITTEE_FEE);
        assertEq(escrow.feeCredits(memberAddrs[1]), COMMITTEE_FEE);
        assertEq(escrow.feeCredits(memberAddrs[2]), 0);
        assertEq(escrow.totalUncollectedFees(), 2 * COMMITTEE_FEE);
    }

    /// Members pull what they are owed; the escrow only ever transfers out
    /// credited amounts and the accounting identity holds after collection.
    function testCollectFees() public {
        escrow = _deployAndAward(3);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100, 101)));

        vm.prank(memberAddrs[0]);
        escrow.collectFees();
        assertEq(token.balanceOf(memberAddrs[0]), COMMITTEE_FEE);
        assertEq(escrow.feeCredits(memberAddrs[0]), 0);
        assertEq(escrow.totalUncollectedFees(), COMMITTEE_FEE);
        assertEq(escrow.feesCollected(), COMMITTEE_FEE);

        // balance + released + collected == budget + reserve (nothing leaked).
        assertEq(
            token.balanceOf(address(escrow)) + escrow.totalReleased() + escrow.feesCollected(),
            COST + escrow.feeReserve()
        );

        // Nothing left to collect for the collector or an unsigned member.
        vm.prank(memberAddrs[0]);
        vm.expectRevert(ProjectEscrow.ZeroAmount.selector);
        escrow.collectFees();
        vm.prank(memberAddrs[2]);
        vm.expectRevert(ProjectEscrow.ZeroAmount.selector);
        escrow.collectFees();
    }

    /// No fees until the milestone actually releases - signatures that never
    /// cross the threshold accrue nothing.
    function testNoFeesBeforeMilestoneReleases() public {
        escrow = _deployAndAward(3);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        // Admin alone: below the 3-of-5 rule for M = 3 (builder already
        // committed via submitMilestoneComplete).
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK)));
        assertEq(escrow.totalReleased(), 0);
        assertEq(escrow.feeCredits(memberAddrs[0]), 0);

        // First member joins: release fires and the signing member accrues.
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(100)));
        assertEq(escrow.totalReleased(), AMOUNTS[0]);
        assertEq(escrow.feeCredits(memberAddrs[0]), COMMITTEE_FEE);
        assertEq(escrow.feeCredits(memberAddrs[1]), 0);
    }

    /// The auto-released deposit is not a committee approval: no fees.
    function testNoFeesOnDepositRelease() public {
        vm.prank(creator);
        address governanceAddr = factory.createProject(_projectConfig());
        governance = ProjectGovernance(governanceAddr);
        vrf.addConsumer(subscriptionId, governanceAddr);

        vm.prank(admin);
        governance.acceptProposals();
        for (uint256 i; i < 3; i++) {
            vm.prank(memberAddrs[i]);
            governance.optInForCommittee();
        }

        vm.prank(builder);
        governance.createProposal(
            COMPANY_ID, keccak256("proposal-spec"), keccak256("proposal-ipfs"), COST, true, _proposalMilestones()
        );

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

        assertEq(escrow.totalReleased(), AMOUNTS[0]);
        assertEq(escrow.feeCredits(memberAddrs[0]), 0);
        assertEq(escrow.feeCredits(memberAddrs[1]), 0);
        assertEq(escrow.feeCredits(memberAddrs[2]), 0);
        assertEq(escrow.totalUncollectedFees(), 0);
        // The award funded the budget plus the fee reserve.
        assertEq(token.totalSupply(), COST + escrow.feeReserve());
    }

    /// Zero fee disables compensation: nothing is ever accrued.
    function testCommitteeFeesDisabledWhenZero() public {
        ProjectEscrow impl = new ProjectEscrow();
        address clone = Clones.clone(address(impl));
        escrow = ProjectEscrow(clone);

        gov = address(new DummyGovernance());
        vm.prank(gov);
        escrow.initialize(builder, treasury, address(token), admin, builder, COST, _milestoneAmounts(), 0);
        token.mint(address(escrow), COST + escrow.feeReserve());

        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100)));

        assertEq(escrow.totalReleased(), AMOUNTS[0]);
        assertEq(escrow.feeReserve(), 0);
        assertEq(escrow.totalUncollectedFees(), 0);
    }

    /// The factory mints only for registered projects and their own escrows.
    function testFactoryMintsOnlyForOwnEscrow() public {
        _deployAndAward(3);

        vm.prank(outsider);
        vm.expectRevert(ProjectFactory.ProjectNonExistent.selector);
        factory.mintInitialSupplyForProject(address(escrow), COST);

        vm.prank(address(governance));
        vm.expectRevert(ProjectFactory.ProjectNonExistent.selector);
        factory.mintInitialSupplyForProject(address(0xdead), COST);
    }

    // --------------------------------------------------------------------------
    // ------------------------------ COMPANY REGISTRY --------------------------
    // --------------------------------------------------------------------------

    /// Registration stores the minimum set: sequential id, admin wallet,
    /// payment wallet and information hash (read via the public mapping
    /// getter).
    function testCompanyRegistrationStoresData() public {
        vm.prank(memberAddrs[0]);
        uint256 companyId = registry.registerCompany(paymentWallet, keccak256("second company info"));

        assertEq(companyId, 2);
        (address adminWallet, address companyPaymentWallet, bytes32 infoHash, bool companyActive) =
            registry.companies(companyId);
        assertEq(adminWallet, memberAddrs[0]);
        assertEq(companyPaymentWallet, paymentWallet);
        assertEq(infoHash, keccak256("second company info"));
        assertTrue(companyActive);
        assertEq(registry.companyIdOfAdmin(memberAddrs[0]), companyId);
    }

    /// One wallet, one company: a second registration reverts.
    function testCompanyDuplicateAdminRejected() public {
        vm.prank(builder);
        vm.expectRevert(CompanyRegistry.AlreadyRegistered.selector);
        registry.registerCompany(paymentWallet, keccak256("dup"));
    }

    /// Only the company admin can update; changes are reflected on read.
    function testCompanyUpdateByAdminOnly() public {
        vm.prank(outsider);
        vm.expectRevert(CompanyRegistry.NotRegistered.selector);
        registry.updateCompany(paymentWallet, keccak256("hijack"));

        vm.prank(builder);
        registry.updateCompany(paymentWallet, keccak256("new info"));

        (address updatedAdmin, address updatedPaymentWallet, bytes32 updatedInfoHash,) = registry.companies(COMPANY_ID);
        assertEq(updatedAdmin, builder);
        assertEq(updatedPaymentWallet, paymentWallet);
        assertEq(updatedInfoHash, keccak256("new info"));
    }

    /// Bidding requires a registered company: invalid ids yield a zeroed
    /// (inactive) company, and unregistered wallets fail the admin check.
    function testProposalRequiresRegisteredCompany() public {
        _deployProject();

        vm.prank(outsider);
        vm.expectRevert(CompanyRegistry.CompanyNotActive.selector);
        governance.createProposal(999, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());

        vm.prank(outsider);
        vm.expectRevert(ProjectGovernance.UnauthorisedCalled.selector);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());
    }

    /// A company's proposal can only be submitted by its own admin wallet,
    /// even if the caller is another registered company.
    function testProposalRequiresCompanyAdmin() public {
        vm.prank(memberAddrs[0]);
        registry.registerCompany(builder, keccak256("second company"));
        _deployProject();

        vm.prank(memberAddrs[0]);
        vm.expectRevert(ProjectGovernance.UnauthorisedCalled.selector);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());
    }

    /// Proposals read wallets from the registry: the company's payment wallet
    /// becomes the fund wallet and the escrow's builder signer.
    function testProposalUsesCompanyPaymentWallet() public {
        vm.prank(memberAddrs[0]);
        registry.registerCompany(paymentWallet, keccak256("second company"));
        _deployProject();

        for (uint256 i; i < 3; i++) {
            vm.prank(memberAddrs[i]);
            governance.optInForCommittee();
        }

        vm.prank(memberAddrs[0]);
        governance.createProposal(
            2, keccak256("proposal-spec"), keccak256("proposal-ipfs"), COST, false, _proposalMilestones()
        );

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

        // The proposal carried no wallets: they came from the registry.
        // (The public getter flattens the struct without the dynamic array.)
        (,, address proposalAdmin,,,,) = governance.proposals(0);
        assertEq(proposalAdmin, memberAddrs[0]);
        assertEq(escrow.projectWallet(), paymentWallet);
        assertEq(escrow.builderSigner(), paymentWallet);

        // The builder (payment wallet) can run the escrow normally.
        vm.prank(paymentWallet);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100)));
        assertEq(escrow.totalReleased(), AMOUNTS[0]);
        assertEq(token.balanceOf(paymentWallet), AMOUNTS[0]);
    }

    // --------------------------------------------------------------------------
    // -------------------------------- CANCELLATION -----------------------------
    // --------------------------------------------------------------------------

    function testThreeMembersCannotCancel() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        bytes32 reason = keccak256("builder abandoned site");
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(100, 101, 102)));

        assertFalse(escrow.cancelled());
        assertEq(token.balanceOf(treasury), 0);
        assertEq(escrow.cancellationApprovalCount(), 3);

        // 4th signature triggers the redirect.
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(ADMIN_PK)));

        assertTrue(escrow.cancelled());
        assertEq(escrow.totalReturnedOnCancellation(), COST + escrow.feeReserve());
        assertEq(token.balanceOf(treasury), COST + escrow.feeReserve());
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function testCancellationAfterPartialReleasesRedirectsRemainder() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100)));
        assertEq(escrow.totalReleased(), AMOUNTS[0]);

        bytes32 reason = keccak256("abandoned after first payment");
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(100, 101, 102, ADMIN_PK)));

        assertTrue(escrow.cancelled());
        // The refund keeps the member's uncollected fee in the escrow.
        assertEq(token.balanceOf(treasury), COST + escrow.feeReserve() - AMOUNTS[0] - COMMITTEE_FEE);
        assertEq(escrow.totalUncollectedFees(), COMMITTEE_FEE);

        // The fee is still collectable after cancellation.
        vm.prank(memberAddrs[0]);
        escrow.collectFees();
        assertEq(token.balanceOf(memberAddrs[0]), COMMITTEE_FEE);
        assertEq(escrow.totalUncollectedFees(), 0);
        assertEq(token.balanceOf(address(escrow)), 0);
    }

    function testCancellationReasonIsLocked() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        bytes32 reason = keccak256("breach");
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(100)));
        assertEq(escrow.cancellationReasonHash(), reason);

        bytes32 otherReason = keccak256("different reason");
        ProjectEscrow.Signature[] memory sigs = _cancellationSigs(otherReason, toUint256Array(101));
        vm.expectRevert(ProjectEscrow.ReasonMismatch.selector);
        escrow.approveCancellation(otherReason, sigs);
    }

    function testM0CancellationNeedsBothSigners() public {
        _newEscrow();
        _setMembers(new uint256[](0), new uint256[](0));

        bytes32 reason = keccak256("both sides agree to stop");
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(ADMIN_PK)));
        assertFalse(escrow.cancelled());

        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(BUILDER_PK)));
        assertTrue(escrow.cancelled());
        assertEq(token.balanceOf(treasury), COST + escrow.feeReserve());
    }

    function testCancellationBlocksMilestoneFlow() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        bytes32 reason = keccak256("breach");
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(100, 101, 102, ADMIN_PK)));

        vm.prank(builder);
        vm.expectRevert(ProjectEscrow.ProjectCancelled.selector);
        escrow.submitMilestoneComplete(EVIDENCE);
    }

    function testAbortBeforeFinalizationRefundsTreasury() public {
        _newEscrow();

        vm.prank(gov);
        escrow.abort();

        assertTrue(escrow.cancelled());
        assertEq(token.balanceOf(treasury), COST + escrow.feeReserve());
        assertEq(escrow.totalReturnedOnCancellation(), COST + escrow.feeReserve());
    }

    function testAbortAfterFinalizationReverts() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(gov);
        vm.expectRevert(ProjectEscrow.CommitteeAlreadyFinalized.selector);
        escrow.abort();
    }

    function testSettlementPaidToBuilderBeforeCancellation() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(gov);
        escrow.releaseSettlement(100);
        assertEq(token.balanceOf(builder), 100);

        bytes32 reason = keccak256("abandoned");
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(100, 101, 102, ADMIN_PK)));

        assertTrue(escrow.cancelled());
        assertEq(token.balanceOf(treasury), COST + escrow.feeReserve() - 100);
    }

    // --------------------------------------------------------------------------
    // ------------------------------ GOVERNANCE / VRF ---------------------------
    // --------------------------------------------------------------------------

    function testOptInRules() public {
        vm.prank(creator);
        address governanceAddr = factory.createProject(_projectConfig());
        governance = ProjectGovernance(governanceAddr);

        vm.prank(admin);
        governance.acceptProposals();

        // Admin cannot opt in - they are a signer regardless.
        vm.prank(admin);
        vm.expectRevert(ProjectGovernance.AdminCannotOptIn.selector);
        governance.optInForCommittee();

        vm.prank(memberAddrs[0]);
        governance.optInForCommittee();

        // Double opt-in rejected.
        vm.prank(memberAddrs[0]);
        vm.expectRevert(ProjectGovernance.AlreadyOptedIn.selector);
        governance.optInForCommittee();
    }

    function testOptInClosedAfterAward() public {
        _deployAndAward(1);

        vm.prank(memberAddrs[1]);
        vm.expectRevert(ProjectGovernance.OptInClosed.selector);
        governance.optInForCommittee();
    }

    function testPoolZeroFallbackTwoOfTwo() public {
        escrow = _deployAndAward(0);

        assertTrue(escrow.committeeFinalized());
        assertEq(escrow.getMemberSigners().length, 0);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK)));

        assertEq(escrow.totalReleased(), AMOUNTS[0]);
    }

    function testPoolThreeEveryoneServesNoVRF() public {
        escrow = _deployAndAward(3);

        assertTrue(escrow.committeeFinalized());
        assertFalse(governance.selectionPending());

        address[] memory members = escrow.getMemberSigners();
        assertEq(members.length, 3);
        assertEq(members[0], memberAddrs[0]);
        assertEq(members[1], memberAddrs[1]);
        assertEq(members[2], memberAddrs[2]);
    }

    function testPoolFourPlusDrawsViaVRF() public {
        escrow = _deployAndAward(6);

        // Escrow not finalised until the coordinator answers.
        assertFalse(escrow.committeeFinalized());
        assertTrue(governance.selectionPending());
        assertEq(governance.selectionRequestId(), 1);

        // Deterministic words: indexes are word % 6 -> [1,2,3,4,5].
        uint256[] memory words = new uint256[](5);
        words[0] = 1;
        words[1] = 2;
        words[2] = 3;
        words[3] = 4;
        words[4] = 5;
        _fulfill(words);

        assertTrue(escrow.committeeFinalized());
        assertFalse(governance.selectionPending());

        address[] memory members = escrow.getMemberSigners();
        assertEq(members.length, 3);
        assertEq(members[0], memberAddrs[1]);
        assertEq(members[1], memberAddrs[2]);
        assertEq(members[2], memberAddrs[3]);

        address[] memory alts = escrow.getAlternates();
        assertEq(alts.length, 2);
        assertEq(alts[0], memberAddrs[4]);
        assertEq(alts[1], memberAddrs[5]);

        // The drawn committee can release milestones like any other.
        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 102)));

        assertEq(escrow.totalReleased(), AMOUNTS[0]);
    }

    function testOnlyCoordinatorCanFulfill() public {
        _deployAndAward(6);

        uint256 requestId = governance.selectionRequestId();
        uint256[] memory words = new uint256[](5);
        vm.prank(outsider);
        vm.expectRevert(
            abi.encodeWithSelector(VRFConsumerBaseV2Plus.OnlyCoordinatorCanFulfill.selector, outsider, address(vrf))
        );
        governance.rawFulfillRandomWords(requestId, words);
    }

    function testWrongRequestIdReverts() public {
        _deployAndAward(6);

        uint256[] memory words = _wordsFrom(42, 5);
        vm.prank(address(vrf));
        vm.expectRevert(ProjectGovernance.InvalidRequestId.selector);
        governance.rawFulfillRandomWords(999, words);
    }

    function testRetrySelectionRequestsNewRandomness() public {
        _deployAndAward(6);
        assertEq(governance.selectionRequestId(), 1);

        vm.prank(admin);
        governance.retryCommitteeSelection();
        assertEq(governance.selectionRequestId(), 2);
        assertTrue(governance.selectionPending());

        uint256[] memory words = _wordsFrom(7, 5);
        vrf.fulfillRandomWordsWithOverride(2, address(governance), words);
        assertTrue(escrow.committeeFinalized());
    }

    function testCancelWhileSelectionPendingAbortsToTreasury() public {
        _deployAndAward(6);
        assertFalse(escrow.committeeFinalized());

        vm.prank(admin);
        governance.cancelProject();

        assertTrue(escrow.cancelled());
        assertEq(token.balanceOf(treasury), COST + escrow.feeReserve());
        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.CANCELLED));
    }

    function testNonAdminCannotAbortWhilePending() public {
        _deployAndAward(6);

        vm.prank(outsider);
        vm.expectRevert();
        governance.cancelProject();
    }

    function testCancelFinalisedPermissionlesslyAfterCommitteeCancellation() public {
        _deployAndAward(3);
        assertTrue(escrow.committeeFinalized());

        bytes32 reason = keccak256("breach");
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(100, 101, 102, ADMIN_PK)));
        assertTrue(escrow.cancelled());

        // Anyone can finalise the lifecycle; the signatures are the proof.
        vm.prank(outsider);
        governance.cancelProject();
        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.CANCELLED));
    }

    function testCancelBeforeEscrowExistsIsAdminOnly() public {
        vm.prank(creator);
        address governanceAddr = factory.createProject(_projectConfig());
        governance = ProjectGovernance(governanceAddr);

        vm.prank(outsider);
        vm.expectRevert();
        governance.cancelProject();

        vm.prank(admin);
        governance.cancelProject();
        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.CANCELLED));
    }

    function testCompleteProjectPermissionless() public {
        _deployAndAward(3);

        for (uint256 m; m < 3; m++) {
            vm.prank(builder);
            escrow.submitMilestoneComplete(keccak256(abi.encode(EVIDENCE, m)));
            escrow.approveMilestone(
                _milestoneSigs(m, keccak256(abi.encode(EVIDENCE, m)), toUint256Array(ADMIN_PK, 100))
            );
        }

        vm.prank(outsider);
        governance.completeProject();
        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.COMPLETE));
    }

    function testDepositReleasedOnAward() public {
        escrow = _deployAndAward(3);

        // No deposit requested: nothing released yet.
        assertEq(escrow.totalReleased(), 0);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100)));
        assertEq(escrow.totalReleased(), AMOUNTS[0]);
    }

    // --------------------------------------------------------------------------
    // ------------------------------ LIFECYCLE HARDENING ------------------------
    // --------------------------------------------------------------------------

    function testVotingClosesByDeadlineNotAdminWhim() public {
        vm.prank(creator);
        address governanceAddr = factory.createProject(_projectConfig());
        governance = ProjectGovernance(governanceAddr);

        vm.prank(admin);
        governance.acceptProposals();
        vm.prank(builder);
        governance.createProposal(
            COMPANY_ID, keccak256("proposal-spec"), keccak256("proposal-ipfs"), COST, false, _proposalMilestones()
        );

        vm.warp(block.timestamp + 9 days);
        vm.prank(admin);
        governance.closeProposalsAndOpenVoting();

        // Cannot close voting before the deadline.
        vm.prank(admin);
        vm.expectRevert(ProjectGovernance.VotingStillOpen.selector);
        governance.closeVoting(5);

        // Vote before deadline works.
        vm.prank(memberAddrs[0]);
        governance.voteForProposal(0);

        // Voting window ends at the deadline - late votes rejected.
        vm.warp(governance.votingDeadline());
        vm.prank(memberAddrs[1]);
        vm.expectRevert(ProjectGovernance.VotingClosed.selector);
        governance.voteForProposal(0);

        // And only now can voting be closed.
        vm.prank(admin);
        governance.closeVoting(5);
        assertEq(uint8(governance.projectLifecycle()), uint8(ProjectGovernance.PROJECT_LIFECYCLE.DELIBERATION));
    }

    // --------------------------------------------------------------------------
    // ------------------------------------ FUZZ ---------------------------------
    // --------------------------------------------------------------------------

    function testFuzzSelectionInvariants(uint256 _poolSize, uint256 _seed) public {
        _poolSize = bound(_poolSize, 4, 12);

        // Fresh project each iteration via a new factory flow.
        vm.prank(creator);
        address governanceAddr = factory.createProject(_projectConfig());
        governance = ProjectGovernance(governanceAddr);
        vrf.addConsumer(subscriptionId, governanceAddr);

        vm.prank(admin);
        governance.acceptProposals();

        for (uint256 i; i < _poolSize; i++) {
            vm.prank(memberAddrs[i]);
            governance.optInForCommittee();
        }

        vm.prank(builder);
        governance.createProposal(
            COMPANY_ID, keccak256("proposal-spec"), keccak256("proposal-ipfs"), COST, false, _proposalMilestones()
        );

        vm.warp(block.timestamp + 9 days);
        vm.prank(admin);
        governance.closeProposalsAndOpenVoting();
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        governance.closeVoting(5);

        vm.prank(admin);
        governance.awardProposal(0);
        escrow = ProjectEscrow(governance.projectEscrow());

        assertTrue(governance.selectionPending());

        uint256 wordCount = _poolSize >= 5 ? 5 : _poolSize;
        uint256[] memory words = _wordsFrom(_seed, wordCount);
        _fulfill(words);

        assertTrue(escrow.committeeFinalized());

        address[] memory members = escrow.getMemberSigners();
        address[] memory alts = escrow.getAlternates();

        uint256 expectedAlts = _poolSize >= 5 ? 2 : _poolSize - 3;
        assertEq(members.length, 3);
        assertEq(alts.length, expectedAlts);

        // All picks come from the pool, are distinct, and never the admin/builder.
        for (uint256 i; i < 3; i++) {
            assertTrue(_inPool(members[i], _poolSize));
            assertNotEq(members[i], admin);
            assertNotEq(members[i], builder);
            for (uint256 j = i + 1; j < 3; j++) {
                assertNotEq(members[i], members[j]);
            }
        }
        for (uint256 i; i < alts.length; i++) {
            assertTrue(_inPool(alts[i], _poolSize));
            assertNotEq(alts[i], admin);
            assertNotEq(alts[i], builder);
            for (uint256 j; j < members.length; j++) {
                assertNotEq(alts[i], members[j]);
            }
            for (uint256 j = i + 1; j < alts.length; j++) {
                assertNotEq(alts[i], alts[j]);
            }
        }
    }

    // --------------------------------------------------------------------------
    // --------------------------------------> EVENTS <---------------------------
    // --------------------------------------------------------------------------

    /// Proposal creation announces the company behind the bid.
    function testProposalCreatedEvent() public {
        _deployProject();

        vm.expectEmit(true, true, true, true, address(governance));
        emit ProjectGovernance.ProposalCreated(0, COMPANY_ID, builder, COST);
        vm.prank(builder);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());
    }

    /// Every lifecycle transition announces itself, and the award announces
    /// the new escrow address (predicted: the clone is governance's first
    /// CREATE). expectEmit is scoped to the governance contract so logs from
    /// the escrow/token/factory interleaved in the same transactions are
    /// skipped.
    function testLifecycleEventsEmitted() public {
        vm.prank(creator);
        address governanceAddr = factory.createProject(_projectConfig());
        governance = ProjectGovernance(governanceAddr);
        vrf.addConsumer(subscriptionId, governanceAddr);

        vm.expectEmit(true, true, false, false, address(governance));
        emit ProjectGovernance.ProjectLifecycleChanged(
            ProjectGovernance.PROJECT_LIFECYCLE.CREATED, ProjectGovernance.PROJECT_LIFECYCLE.PROPOSAL
        );
        vm.prank(admin);
        governance.acceptProposals();

        vm.prank(builder);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());

        vm.expectEmit(true, true, false, false, address(governance));
        emit ProjectGovernance.ProjectLifecycleChanged(
            ProjectGovernance.PROJECT_LIFECYCLE.PROPOSAL, ProjectGovernance.PROJECT_LIFECYCLE.VOTING
        );
        vm.warp(block.timestamp + 9 days);
        vm.prank(admin);
        governance.closeProposalsAndOpenVoting();

        vm.prank(memberAddrs[0]);
        governance.voteForProposal(0);

        vm.expectEmit(true, true, false, false, address(governance));
        emit ProjectGovernance.ProjectLifecycleChanged(
            ProjectGovernance.PROJECT_LIFECYCLE.VOTING, ProjectGovernance.PROJECT_LIFECYCLE.DELIBERATION
        );
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        governance.closeVoting(5);

        // Nonce 1: contract accounts start at nonce 1, so the clone is
        // governance's first CREATE.
        address predictedEscrow = vm.computeCreateAddress(address(governance), 1);
        vm.expectEmit(true, true, false, false, address(governance));
        emit ProjectGovernance.ProjectLifecycleChanged(
            ProjectGovernance.PROJECT_LIFECYCLE.DELIBERATION, ProjectGovernance.PROJECT_LIFECYCLE.AWARDED
        );
        vm.expectEmit(true, true, false, true, address(governance));
        emit ProjectGovernance.ProposalAwarded(0, predictedEscrow, COST);
        vm.prank(admin);
        governance.awardProposal(0);

        // Release every milestone (2-of-2 with no opt-ins), then complete.
        escrow = ProjectEscrow(governance.projectEscrow());
        for (uint256 m; m < 3; m++) {
            vm.prank(builder);
            escrow.submitMilestoneComplete(keccak256(abi.encode(EVIDENCE, m)));
            escrow.approveMilestone(_milestoneSigs(m, keccak256(abi.encode(EVIDENCE, m)), toUint256Array(ADMIN_PK)));
        }

        vm.expectEmit(true, true, false, false, address(governance));
        emit ProjectGovernance.ProjectLifecycleChanged(
            ProjectGovernance.PROJECT_LIFECYCLE.AWARDED, ProjectGovernance.PROJECT_LIFECYCLE.COMPLETE
        );
        governance.completeProject();
    }

    /// Evidence locking and settlements announce their details (scoped to the
    /// escrow so interleaved governance/factory/token logs are skipped).
    function testEscrowStateEventsEmitted() public {
        escrow = _deployAndAward(3);

        vm.expectEmit(true, false, false, true, address(escrow));
        emit ProjectEscrow.MilestoneCompletionSubmitted(0, EVIDENCE);
        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        vm.expectEmit(true, false, false, true, address(escrow));
        emit ProjectEscrow.SettlementPaid(100);
        vm.prank(admin);
        governance.releaseSettlement(100);
    }

    /// Company registration and updates announce on-chain.
    function testCompanyRegistryEventsEmitted() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit CompanyRegistry.CompanyRegistered(2, memberAddrs[0], paymentWallet, keccak256("second company"));
        vm.prank(memberAddrs[0]);
        registry.registerCompany(paymentWallet, keccak256("second company"));

        vm.expectEmit(true, true, false, true, address(registry));
        emit CompanyRegistry.CompanyUpdated(COMPANY_ID, paymentWallet, keccak256("new info"));
        vm.prank(builder);
        registry.updateCompany(paymentWallet, keccak256("new info"));
    }

    // --------------------------------------------------------------------------
    // --------------------------------------> REDEMPTION ------------------------
    // --------------------------------------------------------------------------

    /// Redeeming burns the tokens and mints a transferable receipt NFT.
    function testRedeemBurnsAndMintsReceipt() public {
        token.mint(builder, COST);
        vm.prank(builder);
        token.approve(address(redemption), COST);

        uint256 supplyBefore = token.totalSupply();
        vm.prank(builder);
        uint256 tokenId = redemption.redeem(COST, keccak256("builder bank account"), address(0xE5C0));

        assertEq(tokenId, 1);
        assertEq(token.totalSupply(), supplyBefore - COST);
        assertEq(token.balanceOf(builder), 0);
        assertEq(redemption.ownerOf(tokenId), builder);

        (address redeemer, address escrow, uint256 amount, bytes32 destinationId, Redemption.ReceiptState state,) =
            redemption.receipts(tokenId);
        assertEq(redeemer, builder);
        assertEq(escrow, address(0xE5C0));
        assertEq(amount, COST);
        assertEq(destinationId, keccak256("builder bank account"));
        assertEq(uint8(state), uint8(Redemption.ReceiptState.Pending));
    }

    /// No allowance, no redemption - the pull reverts.
    function testRedeemRequiresAllowance() public {
        token.mint(builder, COST);

        vm.prank(builder);
        vm.expectRevert();
        redemption.redeem(COST, keccak256("bank"), address(0xE5C0));
    }

    /// Zero-amount and zero-destination redemptions are rejected.
    function testRedeemValidatesInputs() public {
        vm.prank(builder);
        vm.expectRevert(Redemption.ZeroAmount.selector);
        redemption.redeem(0, keccak256("bank"), address(0xE5C0));

        vm.prank(builder);
        vm.expectRevert(Redemption.InvalidDestination.selector);
        redemption.redeem(COST, bytes32(0), address(0xE5C0));
    }

    /// Only the paying authority can mark a receipt paid; the payout
    /// reference is recorded on-chain.
    function testMarkPaidByPayerOnly() public {
        token.mint(builder, COST);
        vm.prank(builder);
        token.approve(address(redemption), COST);
        vm.prank(builder);
        uint256 tokenId = redemption.redeem(COST, keccak256("bank"), address(0xE5C0));

        vm.prank(outsider);
        vm.expectRevert();
        redemption.markPaid(tokenId, "TRX-123");

        vm.expectEmit(true, false, false, true, address(redemption));
        emit Redemption.ReceiptPaid(tokenId, "TRX-123");
        redemption.markPaid(tokenId, "TRX-123");

        (,,,, Redemption.ReceiptState state, string memory payoutRef) = redemption.receipts(tokenId);
        assertEq(uint8(state), uint8(Redemption.ReceiptState.Paid));
        assertEq(payoutRef, "TRX-123");
    }

    /// A rejected receipt can never be paid - the redeemer must start a new
    /// redemption.
    function testRejectedReceiptCannotBePaid() public {
        token.mint(builder, COST);
        vm.prank(builder);
        token.approve(address(redemption), COST);
        vm.prank(builder);
        uint256 tokenId = redemption.redeem(COST, keccak256("bank"), address(0xE5C0));

        redemption.markRejected(tokenId, keccak256("destination mismatch"));

        (,,,, Redemption.ReceiptState state,) = redemption.receipts(tokenId);
        assertEq(uint8(state), uint8(Redemption.ReceiptState.Rejected));

        vm.expectRevert(Redemption.NotPending.selector);
        redemption.markPaid(tokenId, "TRX-123");
    }

    /// Receipts are transferable; the state follows the tokenId, not the
    /// owner.
    function testReceiptTransferableAndStateFollowsToken() public {
        token.mint(builder, COST);
        vm.prank(builder);
        token.approve(address(redemption), COST);
        vm.prank(builder);
        uint256 tokenId = redemption.redeem(COST, keccak256("bank"), address(0xE5C0));

        vm.prank(builder);
        redemption.safeTransferFrom(builder, paymentWallet, tokenId);

        assertEq(redemption.ownerOf(tokenId), paymentWallet);

        redemption.markPaid(tokenId, "TRX-999");

        // The state moved with the NFT: the new holder's receipt is Paid.
        (address redeemer,,,, Redemption.ReceiptState state,) = redemption.receipts(tokenId);
        assertEq(redeemer, builder);
        assertEq(uint8(state), uint8(Redemption.ReceiptState.Paid));
    }

    // --------------------------------------------------------------------------
    // ----------------------------- ALTERNATE PROMOTION -------------------------
    // --------------------------------------------------------------------------

    /// A stalled member is replaced by an alternate via signature-gated
    /// promotion (admin + builder + one remaining member).
    function testPromoteAlternateReplacesStaleMember() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), toUint256Array(110));

        // The stale member (100) already signed the current milestone.
        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        // The stale member (100) already signed the current milestone.
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(100)));

        // Admin + builder + member 101 promote alternate 110 over member 100.
        uint256[] memory promoPks = new uint256[](3);
        promoPks[0] = ADMIN_PK;
        promoPks[1] = BUILDER_PK;
        promoPks[2] = 101;
        escrow.promoteAlternate(0, 0, _promotionSigs(0, 0, promoPks));

        address[] memory members = escrow.getMemberSigners();
        assertEq(members[0], memberAddrs[10]);
        assertEq(members[1], memberAddrs[1]);
        assertEq(members[2], memberAddrs[2]);
        assertEq(escrow.getAlternates().length, 0);

        // The promoted member can sign the current milestone fresh - the
        // stale slot's bits were cleared. Admin joins to reach the 3-of-5
        // rule (builder submitted + admin + promoted member).
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 110)));
        assertEq(escrow.totalReleased(), AMOUNTS[0]);

        // The promoted member accrues the fee, not the stale member (the
        // direct escrow funds no fee reserve, so only the credit is asserted).
        assertEq(escrow.feeCredits(memberAddrs[10]), COMMITTEE_FEE);
        assertEq(escrow.feeCredits(memberAddrs[0]), 0);
        assertEq(escrow.totalUncollectedFees(), COMMITTEE_FEE);
    }

    /// M=1: admin + builder alone may swap the single member.
    function testPromoteAlternateSingleMember() public {
        _newEscrow();
        _setMembers(toUint256Array(100), toUint256Array(110));

        uint256[] memory promoPks = new uint256[](2);
        promoPks[0] = ADMIN_PK;
        promoPks[1] = BUILDER_PK;
        escrow.promoteAlternate(0, 0, _promotionSigs(0, 0, promoPks));

        assertEq(escrow.getMemberSigners()[0], memberAddrs[10]);
    }

    /// Insufficient promotion signatures never swap anyone.
    function testPromoteAlternateNeedsThreshold() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), toUint256Array(110));

        // Admin + one member only: below the rule.
        ProjectEscrow.Signature[] memory sigs = _promotionSigs(0, 0, toUint256Array(ADMIN_PK, 101));
        vm.expectRevert(ProjectEscrow.InvalidSignature.selector);
        escrow.promoteAlternate(0, 0, sigs);

        assertEq(escrow.getMemberSigners()[0], memberAddrs[0]);
    }

    /// Promotion requires valid indices.
    function testPromoteAlternateValidatesIndices() public {
        // No alternates drawn: promotion impossible.
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        ProjectEscrow.Signature[] memory noAltSigs = _promotionSigs(0, 0, toUint256Array(ADMIN_PK, BUILDER_PK));
        vm.expectRevert(ProjectEscrow.NoAlternates.selector);
        escrow.promoteAlternate(0, 0, noAltSigs);

        // Fresh escrow with alternates: index bounds are enforced.
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), toUint256Array(110));

        ProjectEscrow.Signature[] memory badAltSigs = _promotionSigs(1, 0, toUint256Array(ADMIN_PK, BUILDER_PK));
        vm.expectRevert(ProjectEscrow.InvalidAlternateIndex.selector);
        escrow.promoteAlternate(1, 0, badAltSigs);

        ProjectEscrow.Signature[] memory badMemberSigs = _promotionSigs(0, 3, toUint256Array(ADMIN_PK, BUILDER_PK));
        vm.expectRevert(ProjectEscrow.InvalidMemberIndex.selector);
        escrow.promoteAlternate(0, 3, badMemberSigs);
    }

    /// A member replaced after signing cancellation loses that signature:
    /// the promoted alternate can sign cancellation fresh.
    function testPromoteClearsCancellationBits() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), toUint256Array(110));

        bytes32 reason = keccak256("stall");
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(100)));

        uint256[] memory promoPks = new uint256[](3);
        promoPks[0] = ADMIN_PK;
        promoPks[1] = BUILDER_PK;
        promoPks[2] = 101;
        escrow.promoteAlternate(0, 0, _promotionSigs(0, 0, promoPks));

        // The promoted member can sign the cancellation now.
        escrow.approveCancellation(reason, _cancellationSigs(reason, toUint256Array(110)));
        assertTrue(escrow.hasSignedCancellation(memberAddrs[10]));
    }

    // --------------------------------------------------------------------------
    // ------------------------------ ERC-1271 SIGNERS ---------------------------
    // --------------------------------------------------------------------------

    /// A member whose identity is a smart wallet (ERC-1271) can approve via
    /// the wallet's owner key - the account-abstraction future.
    function testERC1271MemberCanApprove() public {
        _newEscrow();
        MockERC1271Wallet wallet = new MockERC1271Wallet(memberAddrs[0]);

        address[] memory members = new address[](3);
        members[0] = address(wallet);
        members[1] = memberAddrs[1];
        members[2] = memberAddrs[2];
        address[] memory alts;
        vm.prank(gov);
        escrow.setCommitteeMembers(members, alts);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        // Sign as the wallet's owner (pk 100), packed for the wallet.
        bytes32 digest = escrow.getMilestoneApprovalDigest(0, EVIDENCE, address(wallet));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(100, digest);
        bytes memory walletSig = abi.encode(v, r, s);

        ProjectEscrow.Signature[] memory sigs = new ProjectEscrow.Signature[](2);
        sigs[0] = ProjectEscrow.Signature({signer: address(wallet), signature: walletSig});
        sigs[1] = ProjectEscrow.Signature({
            signer: admin,
            signature: _sign(ADMIN_PK, escrow.getMilestoneApprovalDigest(0, EVIDENCE, admin))
        });

        escrow.approveMilestone(sigs);
        assertEq(escrow.totalReleased(), AMOUNTS[0]);
    }

    /// A non-owner signature on a smart wallet is rejected.
    function testERC1271RejectsForeignSignature() public {
        _newEscrow();
        MockERC1271Wallet wallet = new MockERC1271Wallet(memberAddrs[0]);

        address[] memory members = new address[](3);
        members[0] = address(wallet);
        members[1] = memberAddrs[1];
        members[2] = memberAddrs[2];
        address[] memory alts;
        vm.prank(gov);
        escrow.setCommitteeMembers(members, alts);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        bytes32 digest = escrow.getMilestoneApprovalDigest(0, EVIDENCE, address(wallet));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(101, digest); // wrong owner
        bytes memory walletSig = abi.encode(v, r, s);

        ProjectEscrow.Signature[] memory sigs = new ProjectEscrow.Signature[](1);
        sigs[0] = ProjectEscrow.Signature({signer: address(wallet), signature: walletSig});

        vm.expectRevert(ProjectEscrow.InvalidSignature.selector);
        escrow.approveMilestone(sigs);
    }

    // --------------------------------------------------------------------------
    // ------------------------------- BATCH EDGES -------------------------------
    // --------------------------------------------------------------------------

    /// A duplicate signer inside one batch reverts.
    function testDuplicateSignerInBatchReverts() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        ProjectEscrow.Signature[] memory sigs = new ProjectEscrow.Signature[](2);
        sigs[0] = _milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK))[0];
        sigs[1] = _milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK))[0];

        vm.expectRevert(ProjectEscrow.AlreadySigned.selector);
        escrow.approveMilestone(sigs);
    }

    /// A signer outside the committee cannot approve.
    function testNonCommitteeSignerRejected() public {
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);

        ProjectEscrow.Signature[] memory sigs = _milestoneSigs(0, EVIDENCE, toUint256Array(OUTSIDER_PK));
        vm.expectRevert(ProjectEscrow.NotSigner.selector);
        escrow.approveMilestone(sigs);
    }

    // --------------------------------------------------------------------------
    // ----------------------------- FEES BY COMMITTEE ---------------------------
    // --------------------------------------------------------------------------

    /// M=2 integration: fees accrue to the two signing members via the real
    /// stack (award funds the reserve, members collect their credits).
    function testFeesM2Integration() public {
        escrow = _deployAndAward(2);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100, 101)));

        assertEq(escrow.feeCredits(memberAddrs[0]), COMMITTEE_FEE);
        assertEq(escrow.feeCredits(memberAddrs[1]), COMMITTEE_FEE);
        assertEq(escrow.feeCredits(memberAddrs[2]), 0);

        vm.prank(memberAddrs[1]);
        escrow.collectFees();
        assertEq(token.balanceOf(memberAddrs[1]), COMMITTEE_FEE);
        assertEq(escrow.totalUncollectedFees(), COMMITTEE_FEE);
    }

    /// M=1 integration: the single member collects the accrued fee.
    function testFeesM1Integration() public {
        escrow = _deployAndAward(1);

        vm.prank(builder);
        escrow.submitMilestoneComplete(EVIDENCE);
        escrow.approveMilestone(_milestoneSigs(0, EVIDENCE, toUint256Array(ADMIN_PK, 100)));

        assertEq(escrow.feeCredits(memberAddrs[0]), COMMITTEE_FEE);

        vm.prank(memberAddrs[0]);
        escrow.collectFees();
        assertEq(token.balanceOf(memberAddrs[0]), COMMITTEE_FEE);
    }

    // --------------------------------------------------------------------------
    // ----------------------------- FEE SURPLUS SWEEP --------------------------
    // --------------------------------------------------------------------------

    /// Completion sweeps the un-owed fee reserve to the treasury; members
    /// keep their accrued fees, collectable at any time.
    function testCompletionSweepsUnusedFeeReserve() public {
        escrow = _deployAndAward(2); // M = 2: reserve 90, max accrual 60.

        for (uint256 m; m < 3; m++) {
            bytes32 evidence = keccak256(abi.encode("stage", m));
            vm.prank(builder);
            escrow.submitMilestoneComplete(evidence);
            // Member 100 signs every milestone (30), member 101 only the
            // first (10): accrued 40, un-owed surplus 50.
            uint256[] memory pks = m == 0 ? toUint256Array(ADMIN_PK, 100, 101) : toUint256Array(ADMIN_PK, 100);
            escrow.approveMilestone(_milestoneSigs(m, evidence, pks));
        }
        assertTrue(escrow.allMilestonesReleased());
        assertEq(escrow.totalUncollectedFees(), 4 * COMMITTEE_FEE);

        // Completion sweeps the surplus (90 - 40 = 50) to the treasury.
        vm.prank(admin);
        governance.completeProject();
        assertEq(escrow.totalSweptToTreasury(), 50);
        assertEq(token.balanceOf(treasury), 50);
        assertEq(token.balanceOf(address(escrow)), 4 * COMMITTEE_FEE);

        // The members' accrued fees remain collectable, without a deadline.
        vm.warp(block.timestamp + 400 days);
        vm.prank(memberAddrs[0]);
        escrow.collectFees();
        assertEq(token.balanceOf(memberAddrs[0]), 3 * COMMITTEE_FEE);
        vm.prank(memberAddrs[1]);
        escrow.collectFees();
        assertEq(token.balanceOf(memberAddrs[1]), COMMITTEE_FEE);
        assertEq(escrow.totalUncollectedFees(), 0);
        assertEq(token.balanceOf(address(escrow)), 0);

        // The surplus sweep is idempotent: a second call sweeps nothing.
        vm.prank(address(governance));
        escrow.sweepSurplusToTreasury();
        assertEq(escrow.totalSweptToTreasury(), 50);
        assertEq(token.balanceOf(treasury), 50);
    }

    // --------------------------------------------------------------------------
    // ---------------------------------- HELPERS --------------------------------
    // --------------------------------------------------------------------------

    /// Builds EIP-712 promotion signatures for the given private keys.
    function _promotionSigs(uint256 _alt, uint256 _member, uint256[] memory _pks)
        internal
        returns (ProjectEscrow.Signature[] memory sigs)
    {
        sigs = new ProjectEscrow.Signature[](_pks.length);
        for (uint256 i; i < _pks.length; i++) {
            address signer = vm.addr(_pks[i]);
            bytes32 digest = escrow.getAlternatePromotionDigest(_alt, _member, signer);
            sigs[i] = ProjectEscrow.Signature({signer: signer, signature: _sign(_pks[i], digest)});
        }
    }
}
