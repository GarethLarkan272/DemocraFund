// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ProjectEscrow} from "../src/ProjectEscrow.sol";
import {PaymentToken} from "../src/PaymentToken.sol";

/// @notice Randomised action driver for the escrow. Every call is a legal
///         (revert-free) action: builder submits evidence, random signer
///         subsets approve milestones, random cancellation attempts,
///         alternate promotions, and settlements.
contract EscrowInvariantHandler is Test {
    ProjectEscrow public escrow;
    PaymentToken public token;

    address internal constant GOV = address(0x60A);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant DUMMY_PAYER = address(0xFE3);

    /// forge-lint: disable-next-line(mixed-case-variable) // Mirrors the ADMIN_PK/BUILDER_PK constants.
    address internal ADMIN;
    /// forge-lint: disable-next-line(mixed-case-variable) // Mirrors the ADMIN_PK/BUILDER_PK constants.
    address internal BUILDER;

    uint256[] memberPks = [100, 101, 102];
    address[] members;
    address[] alts;
    mapping(address => uint256) internal pkOf;

    uint256 internal constant BUDGET = 1000;
    uint256 internal constant FEE = 10;
    bytes32 internal constant EVIDENCE = keccak256("evidence");
    bytes32 internal constant REASON = keccak256("cancel-reason"); // one shared, locked reason

    /// @notice Pre-sign the dummy governance + fund the escrow (budget plus
    ///          the committee fee reserve) + finalise a 3-member committee
    ///          with 2 alternates.
    constructor() {
        token = new PaymentToken(address(this));
        token.setFactoryRole(address(this));

        // Admin/builder are real key-derived addresses so the handler can
        // sign for them.
        ADMIN = vm.addr(ADMIN_PK);
        BUILDER = vm.addr(BUILDER_PK);
        pkOf[ADMIN] = ADMIN_PK;
        pkOf[BUILDER] = BUILDER_PK;

        ProjectEscrow impl = new ProjectEscrow();
        address clone = Clones.clone(address(impl));
        escrow = ProjectEscrow(clone);

        // DUMMY_PAYER is the escrow's controller (initialize/abort/
        // releaseSettlement) - it needs no code, it is just an address.
        vm.prank(DUMMY_PAYER);
        escrow.initialize(BUILDER, TREASURY, address(token), ADMIN, BUILDER, BUDGET, _amounts(), FEE);
        token.mint(address(escrow), BUDGET + escrow.feeReserve());

        // Members 100-102, alternates 103-104: all signable, so promoted
        // alternates can keep approving and cancelling.
        for (uint256 i; i < memberPks.length; i++) {
            address m = vm.addr(memberPks[i]);
            members.push(m);
            pkOf[m] = memberPks[i];
        }
        alts = new address[](2);
        alts[0] = vm.addr(103);
        alts[1] = vm.addr(104);
        pkOf[alts[0]] = 103;
        pkOf[alts[1]] = 104;

        vm.prank(DUMMY_PAYER);
        escrow.setCommitteeMembers(members, alts);
    }

    /// @notice Builder declares the current milestone complete.
    function submit() external {
        if (escrow.cancelled()) return;
        if (escrow.currentMilestoneIndex() >= 3) return;
        if (escrow.hasSigned(escrow.currentMilestoneIndex(), BUILDER)) return;

        vm.prank(BUILDER);
        escrow.submitMilestoneComplete(EVIDENCE);
    }

    /// @notice A random subset of admin + members signs the current milestone.
    function approve(uint256 _rng) external {
        if (escrow.cancelled()) return;
        uint256 index = escrow.currentMilestoneIndex();
        if (index >= 3) return;

        // Approvals only exist once the builder locked the evidence.
        (, bytes32 evidence,) = escrow.milestones(index);
        if (evidence == bytes32(0)) return;

        ProjectEscrow.Signature[] memory sigs = new ProjectEscrow.Signature[](4);
        uint256 count;
        if (_rng & 1 != 0 && !escrow.hasSigned(index, ADMIN)) {
            sigs[count++] = _milestoneSig(index, ADMIN);
        }
        for (uint256 i; i < members.length; i++) {
            if ((_rng >> (i + 1)) & 1 != 0 && !escrow.hasSigned(index, members[i])) {
                sigs[count++] = _milestoneSig(index, members[i]);
            }
        }
        if (count > 0) {
            ProjectEscrow.Signature[] memory trimmed = _trim(sigs, count);
            escrow.approveMilestone(trimmed);
        }
    }

    /// @notice A random subset of all signers attempts a cancellation.
    function cancel(uint256 _rng) external {
        if (escrow.cancelled()) return;
        bytes32 reason = REASON;

        ProjectEscrow.Signature[] memory sigs = new ProjectEscrow.Signature[](5);
        uint256 count;
        address[] memory all = _allSigners();
        for (uint256 i; i < all.length; i++) {
            if ((_rng >> i) & 1 != 0 && !escrow.hasSignedCancellation(all[i])) {
                bytes32 digest = escrow.getCancellationApprovalDigest(reason, all[i]);
                sigs[count++] = ProjectEscrow.Signature({signer: all[i], signature: _sign(pkOf[all[i]], digest)});
            }
        }
        if (count > 0) {
            escrow.approveCancellation(reason, _trim(sigs, count));
        }
    }

    /// @notice Promotes a random alternate over a random member.
    function promote(uint256 _rng) external {
        if (escrow.cancelled()) return;
        if (escrow.getAlternates().length == 0) return;

        uint256 altIdx = _rng % escrow.getAlternates().length;
        uint256 memberIdx = (_rng >> 8) % members.length;
        uint256 other = (memberIdx + 1) % members.length;

        ProjectEscrow.Signature[] memory sigs = new ProjectEscrow.Signature[](3);
        sigs[0] = _promotionSig(altIdx, memberIdx, ADMIN);
        sigs[1] = _promotionSig(altIdx, memberIdx, BUILDER);
        sigs[2] = _promotionSig(altIdx, memberIdx, members[other]);

        escrow.promoteAlternate(altIdx, memberIdx, sigs);
        members[memberIdx] = escrow.getMemberSigners()[memberIdx];
    }
    /// @notice Admin pays a random settlement, capped by what is left after
    ///         releases, prior settlements, AND the unreleased milestone
    ///         schedule - so a settlement can never starve the remaining
    ///         milestones (that would brick their release).

    function settle(uint256 _rng) external {
        if (escrow.cancelled()) return;
        uint256 index = escrow.currentMilestoneIndex();
        uint256 reserved;
        for (uint256 i = index; i < 3; i++) {
            (uint256 milestoneAmount,,) = escrow.milestones(i);
            reserved += milestoneAmount;
        }
        uint256 available = escrow.totalProjectBudget() - escrow.totalReleased() - escrow.settlementPaid() - reserved;
        if (available == 0) return;
        uint256 amount = (_rng % 50) * (available / 50) + (_rng % (available % 50 + 1));
        if (amount > available) amount = available;

        vm.prank(DUMMY_PAYER);
        escrow.releaseSettlement(amount);
    }

    /// @notice A random member collects their accrued committee fees.
    function collect(uint256 _rng) external {
        if (members.length == 0) return;
        address member = members[_rng % members.length];
        if (escrow.feeCredits(member) == 0) return;

        vm.prank(member);
        escrow.collectFees();
    }

    /// @notice Sweeps the un-owed fee reserve once every milestone released.
    function sweepSurplus() external {
        if (escrow.cancelled() || !escrow.allMilestonesReleased()) return;

        vm.prank(DUMMY_PAYER);
        escrow.sweepSurplusToTreasury();
    }

    /// @notice All signers (admin + members + builder) for cancellation draws.
    function _allSigners() internal view returns (address[] memory all) {
        all = new address[](members.length + 2);
        all[0] = ADMIN;
        all[members.length + 1] = BUILDER;
        for (uint256 i; i < members.length; i++) {
            all[i + 1] = members[i];
        }
    }

    function _milestoneSig(uint256 _index, address _signer) internal returns (ProjectEscrow.Signature memory) {
        bytes32 digest = escrow.getMilestoneApprovalDigest(_index, EVIDENCE, _signer);
        return ProjectEscrow.Signature({signer: _signer, signature: _sign(pkOf[_signer], digest)});
    }

    function _promotionSig(uint256 _alt, uint256 _member, address _signer)
        internal
        returns (ProjectEscrow.Signature memory)
    {
        bytes32 digest = escrow.getAlternatePromotionDigest(_alt, _member, _signer);
        return ProjectEscrow.Signature({signer: _signer, signature: _sign(pkOf[_signer], digest)});
    }

    function _sign(uint256 _pk, bytes32 _digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pk, _digest);
        return abi.encodePacked(r, s, v);
    }

    function _trim(ProjectEscrow.Signature[] memory _sigs, uint256 _count)
        internal
        pure
        returns (ProjectEscrow.Signature[] memory trimmed)
    {
        trimmed = new ProjectEscrow.Signature[](_count);
        for (uint256 i; i < _count; i++) {
            trimmed[i] = _sigs[i];
        }
    }

    function _amounts() internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](3);
        amounts[0] = 300;
        amounts[1] = 300;
        amounts[2] = 400;
    }

    uint256 internal constant ADMIN_PK = 1001;
    uint256 internal constant BUILDER_PK = 1002;
}

/// @title EscrowInvariantTest
/// @notice Invariant fuzzing over the escrow's fund movement: no matter what
///         sequence of legal actions the handler takes, the escrow's
///         accounting stays exact and its lifecycle stays coherent.
contract EscrowInvariantTest is Test {
    EscrowInvariantHandler internal handler;

    function setUp() public {
        handler = new EscrowInvariantHandler();
        targetContract(address(handler));
    }

    /// The handler genuinely progresses: a deterministic action sequence
    /// releases milestones or cancels - the reverts seen during fuzzing are
    /// not starving the state space.
    function testHandlerProgresses() public {
        for (uint256 i; i < 200; i++) {
            handler.submit();
            handler.approve(i);
            handler.cancel(i >> 1);
            handler.promote(i >> 2);
            handler.settle(i >> 3);
        }
        assertTrue(
            handler.escrow().currentMilestoneIndex() >= 1 || handler.escrow().cancelled(),
            "no milestone released and no cancellation in 200 action rounds"
        );
    }

    /// Total supply discipline: escrow balance + everything paid out is
    /// exactly the funded amount (budget + fee reserve). Committee fees are
    /// funded upfront, never minted at release.
    function invariant_accountingNeverBreaks() public view {
        uint256 balance = handler.token().balanceOf(address(handler.escrow()));
        uint256 released = handler.escrow().totalReleased();
        uint256 settled = handler.escrow().settlementPaid();
        uint256 returned = handler.escrow().totalReturnedOnCancellation();
        uint256 collected = handler.escrow().feesCollected();
        uint256 swept = handler.escrow().totalSweptToTreasury();

        assertEq(
            balance + released + settled + returned + collected + swept,
            handler.escrow().totalProjectBudget() + handler.escrow().feeReserve()
        );
        assertLe(released + settled, handler.escrow().totalProjectBudget());
    }

    /// The escrow never holds less than what members are still owed in fees.
    function invariant_balanceNeverBelowOwedFees() public view {
        assertGe(handler.token().balanceOf(address(handler.escrow())), handler.escrow().totalUncollectedFees());
    }

    /// Accruals never exceed the funded reserve (the escrow can never owe
    /// more fees than it holds).
    function invariant_accrualNeverExceedsReserve() public view {
        assertLe(
            handler.escrow().feesCollected() + handler.escrow().totalUncollectedFees(), handler.escrow().feeReserve()
        );
    }

    /// Releases never overshoot the schedule.
    function invariant_milestoneIndexWithinSchedule() public view {
        assertLe(handler.escrow().currentMilestoneIndex(), 3);
    }

    /// A released milestone always carries locked evidence.
    function invariant_releasedMilestonesHaveEvidence() public view {
        for (uint256 i; i < handler.escrow().currentMilestoneIndex(); i++) {
            (uint256 amount, bytes32 evidence, bool released) = handler.escrow().milestones(i);
            assertGt(amount, 0);
            if (released) {
                assertTrue(evidence != bytes32(0));
            }
        }
    }

    /// Cancellation refunds the treasury everything EXCEPT the outstanding fee
    /// credits: the escrow holds exactly what members can still collect.
    function invariant_cancelledEscrowKeepsFeeFunds() public view {
        if (handler.escrow().cancelled()) {
            assertEq(handler.token().balanceOf(address(handler.escrow())), handler.escrow().totalUncollectedFees());
            assertEq(
                handler.escrow().totalReturnedOnCancellation(),
                handler.escrow().totalProjectBudget() + handler.escrow().feeReserve() - handler.escrow().totalReleased()
                    - handler.escrow().settlementPaid() - handler.escrow().feesCollected()
                    - handler.escrow().totalSweptToTreasury() - handler.escrow().totalUncollectedFees()
            );
        }
    }

    /// Settlements never exceed what remains after releases.
    function invariant_settlementsCapped() public view {
        assertLe(
            handler.escrow().settlementPaid(), handler.escrow().totalProjectBudget() - handler.escrow().totalReleased()
        );
    }
}
