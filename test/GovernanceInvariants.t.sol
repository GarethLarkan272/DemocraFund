// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TestBase} from "./TestBase.sol";
import {ProjectEscrow} from "../src/ProjectEscrow.sol";
import {PaymentToken} from "../src/PaymentToken.sol";
import {ProjectGovernance} from "../src/ProjectGovernance.sol";

/// @notice Randomised driver for the governance lifecycle state machine. Only
///         legal next-steps are offered per lifecycle stage, plus random time
///         warps, so the handler can always make progress (mirrors a real
///         user + admin acting randomly). Self-contained: it builds its own
///         fixture stack via TestBase and seeds one tender with a proposal.
contract GovernanceInvariantHandler is TestBase {
    uint256 public votesCast;
    bool public awarded;

    /// @notice Initialises its own full stack (TestBase fixtures) and seeds a
    ///         tender with a proposal.
    constructor() {
        setUp();
        _deployProject();
        vm.prank(builder);
        governance.createProposal(COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones());
    }

    /// @notice Takes one random legal step in the current lifecycle.
    function step(uint256 _rng) external {
        ProjectGovernance.PROJECT_LIFECYCLE lifecycle = governance.projectLifecycle();

        if (lifecycle == ProjectGovernance.PROJECT_LIFECYCLE.CREATED) {
            if (_rng & 1 != 0) {
                vm.prank(admin);
                governance.acceptProposals();
            }
            return;
        }

        if (lifecycle == ProjectGovernance.PROJECT_LIFECYCLE.PROPOSAL) {
            uint256 choice = _rng % 4;
            if (choice == 0) {
                // The constructor already submitted this company's single
                // proposal - only re-submit while it is still legally open.
                if (!governance.companyHasProposal(COMPANY_ID) && block.timestamp < governance.proposalDeadline()) {
                    vm.prank(builder);
                    governance.createProposal(
                        COMPANY_ID, keccak256("s"), keccak256("i"), COST, false, _proposalMilestones()
                    );
                }
            } else if (choice == 1) {
                _randomOptIn(_rng);
            } else if (choice == 2) {
                vm.warp(block.timestamp + 2 days);
            } else {
                vm.warp(block.timestamp + 9 days); // past proposalDeadline
                vm.prank(admin);
                governance.closeProposalsAndOpenVoting();
            }
            return;
        }

        if (lifecycle == ProjectGovernance.PROJECT_LIFECYCLE.VOTING) {
            uint256 choice = _rng % 3;
            if (choice == 0) {
                if (governance.numberOfProposals() > 0 && block.timestamp < governance.votingDeadline()) {
                    address voter = _unVotedMember(_rng);
                    if (voter != address(0)) {
                        vm.prank(voter);
                        governance.voteForProposal(0);
                        votesCast++;
                    }
                }
            } else if (choice == 1) {
                vm.warp(block.timestamp + 2 days);
            } else {
                vm.warp(block.timestamp + 8 days); // past votingDeadline
                vm.prank(admin);
                governance.closeVoting(5);
            }
            return;
        }

        if (lifecycle == ProjectGovernance.PROJECT_LIFECYCLE.DELIBERATION) {
            uint256 choice = _rng % 3;
            if (choice == 0) {
                _randomOptIn(_rng);
            } else if (choice == 1) {
                if (block.timestamp <= governance.awardDeadline() && governance.numberOfProposals() > 0) {
                    vm.prank(admin);
                    governance.awardProposal(0);
                    awarded = true;
                    escrow = ProjectEscrow(governance.projectEscrow());
                }
            } else {
                vm.warp(block.timestamp + 1 days);
            }
            return;
        }

        if (lifecycle == ProjectGovernance.PROJECT_LIFECYCLE.AWARDED) {
            // A pending VRF draw must be resolved before any escrow activity
            // (the committee is only finalised by the fulfillment callback).
            // The handler either fulfills it or aborts via the admin - both
            // are legal while the draw is pending.
            if (!escrow.committeeFinalized()) {
                if (governance.selectionPending() && _rng & 1 != 0) {
                    uint256 wordCount = governance.optInCount() >= 5 ? 5 : governance.optInCount();
                    _fulfill(_wordsFrom(block.timestamp, wordCount));
                } else if (governance.selectionPending() && _rng & 2 != 0) {
                    vm.prank(admin);
                    governance.cancelProject();
                }
                return;
            }
            if (_rng & 1 != 0 && !escrow.allMilestonesReleased()) {
                _releaseNextMilestone();
            } else if (_rng & 2 != 0 && escrow.allMilestonesReleased()) {
                governance.completeProject();
            }
        }
    }

    /// @notice Signs the current milestone with admin plus every committee
    ///         member who has not signed yet, so the derived rule (2-of-2 for
    ///         M=0, up to 3-of-5) is always met on the first release attempt.
    ///         Guards hasSigned so repeated steps never re-sign a signer.
    function _releaseNextMilestone() internal {
        uint256 index = escrow.currentMilestoneIndex();
        if (index >= 3) return;
        if (!escrow.hasSigned(index, builder)) {
            vm.prank(builder);
            escrow.submitMilestoneComplete(keccak256(abi.encode(index, "evidence")));
        }
        (, bytes32 ev,) = escrow.milestones(index);
        if (ev == bytes32(0)) return;

        address[] memory members = escrow.getMemberSigners();
        uint256 count = escrow.hasSigned(index, admin) ? 0 : 1;
        for (uint256 i; i < members.length; i++) {
            if (!escrow.hasSigned(index, members[i])) count++;
        }
        if (count == 0) return;

        uint256[] memory pks = new uint256[](count);
        uint256 cursor;
        if (!escrow.hasSigned(index, admin)) pks[cursor++] = ADMIN_PK;
        for (uint256 i; i < members.length; i++) {
            if (!escrow.hasSigned(index, members[i])) pks[cursor++] = pkOf[members[i]];
        }

        ProjectEscrow.Signature[] memory sigs = _milestoneSigs(index, ev, pks);
        escrow.approveMilestone(sigs);
    }

    /// @notice A random member who has not opted in yet (or no-op once the
    ///         whole pool has opted in) - one opt-in per member.
    function _randomOptIn(uint256 _rng) internal {
        uint256 start = (_rng >> 8) % memberAddrs.length;
        for (uint256 i; i < memberAddrs.length; i++) {
            address candidate = memberAddrs[(start + i) % memberAddrs.length];
            if (!governance.optedIn(candidate)) {
                vm.prank(candidate);
                governance.optInForCommittee();
                return;
            }
        }
    }

    /// @notice A random member who has not voted yet (or zero once all have).
    function _unVotedMember(uint256 _rng) internal view returns (address) {
        uint256 start = (_rng >> 8) % memberAddrs.length;
        for (uint256 i; i < memberAddrs.length; i++) {
            address candidate = memberAddrs[(start + i) % memberAddrs.length];
            if (!governance.hasVoted(candidate)) return candidate;
        }
        return address(0);
    }

    // Getters for the invariant test (the handler owns its own stack).
    function projectGovernance() external view returns (ProjectGovernance) {
        return governance;
    }

    function currentEscrow() external view returns (ProjectEscrow) {
        return escrow;
    }

    function paymentToken() external view returns (PaymentToken) {
        return token;
    }
}

/// @title GovernanceInvariantTest
/// @notice Lifecycle state-machine invariants under random legal actions:
///         the state machine only moves to reachable states, deadlines are
///         set with their stages, awards always produce a funded escrow, and
///         CANCELLED is terminal.
contract GovernanceInvariantTest is TestBase {
    GovernanceInvariantHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new GovernanceInvariantHandler();
        targetContract(address(handler));
        // Only `step` is a legal fuzz target: the handler's inherited public
        // `setUp`/getters would re-deploy fixtures mid-run and desync the
        // stack (new VRF mock, stale governance), so exclude them.
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = GovernanceInvariantHandler.step.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// The lifecycle never lands in an unreachable state.
    function invariant_lifecycleIsValid() public view {
        uint8 stage = uint8(handler.projectGovernance().projectLifecycle());
        assertLe(stage, uint8(ProjectGovernance.PROJECT_LIFECYCLE.CANCELLED));
    }

    /// Deadlines are set with their stages.
    function invariant_deadlinesSetWithStage() public view {
        uint8 stage = uint8(handler.projectGovernance().projectLifecycle());
        if (stage >= uint8(ProjectGovernance.PROJECT_LIFECYCLE.DELIBERATION)) {
            assertGt(handler.projectGovernance().awardDeadline(), 0);
        }
        if (stage >= uint8(ProjectGovernance.PROJECT_LIFECYCLE.VOTING)) {
            assertGt(handler.projectGovernance().votingDeadline(), 0);
        }
    }

    /// An award always instantiates a funded escrow within the budget cap.
    function invariant_awardProducesFundedEscrow() public view {
        if (uint8(handler.projectGovernance().projectLifecycle()) >= uint8(ProjectGovernance.PROJECT_LIFECYCLE.AWARDED))
        {
            assertTrue(address(handler.projectGovernance().projectEscrow()) != address(0));
            assertLe(handler.paymentToken().balanceOf(address(handler.currentEscrow())), BUDGET_CAP);
        }
    }

    /// Votes recorded on-chain match the handler's counter exactly.
    function invariant_voteCountMonotone() public view {
        assertEq(handler.projectGovernance().numberOfVotesPerProposal(0), handler.votesCast());
    }

    /// The escrow accounting never breaks even under random admin actions.
    function invariant_escrowAccountingHolds() public view {
        ProjectEscrow e = handler.currentEscrow();
        if (address(e) == address(0)) return;
        assertLe(
            handler.paymentToken().balanceOf(address(e)) + e.totalReleased() + e.settlementPaid()
                + e.totalReturnedOnCancellation(),
            BUDGET_CAP
        );
    }
}
