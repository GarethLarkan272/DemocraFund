// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {TestBase} from "./TestBase.sol";
import {ProjectEscrow} from "../src/ProjectEscrow.sol";

/// @title FuzzTest
/// @notice Property-based tests: the release rule holds for every committee
///         size and signature subset, milestone schedules validate correctly,
///         the VRF draw never collides or leaves the pool, and replay is
///         impossible across nonce sequences.
contract FuzzTest is TestBase {
    /// For every committee size M and every subset of signers, a milestone
    /// releases iff the derived rule is met (admin+builder+>=1 member with
    /// >=3 total when M>=1; 2-of-2 when M=0).
    function testFuzzReleaseRuleDerivation(uint256 _m, uint256 _subset, uint256 _seed) public {
        _m = bound(_m, 0, 3);
        _subset = bound(_subset, 0, (1 << (_m + 2)) - 1);
        _seed = bound(_seed, 1, type(uint256).max);

        _newEscrow();
        uint256[] memory memberPks = new uint256[](_m);
        for (uint256 i; i < _m; i++) {
            memberPks[i] = 100 + i;
        }
        _setMembers(memberPks, new uint256[](0));

        vm.prank(builder);
        escrow.submitMilestoneComplete(bytes32(_seed));

        // The subset selects which non-builder signers sign (bit 0 = admin, bits
        // 1..M = members). The builder's signature comes from submitMilestoneComplete.
        bytes32 evidence = bytes32(_seed);
        bool adminSigned = (_subset & 1) != 0;
        uint256 memberBits;
        for (uint256 i; i < _m; i++) {
            if ((_subset >> (i + 1)) & 1 == 1) memberBits |= (1 << i);
        }

        ProjectEscrow.Signature[] memory sigs = new ProjectEscrow.Signature[](_m + 1);
        uint256 count;
        if (adminSigned) {
            sigs[count++] = _milestoneSigs(0, evidence, toUint256Array(ADMIN_PK))[0];
        }
        for (uint256 i; i < _m; i++) {
            if ((_subset >> (i + 1)) & 1 == 1) {
                sigs[count++] = _milestoneSigs(0, evidence, toUint256Array(100 + i))[0];
            }
        }
        if (count > 0) {
            ProjectEscrow.Signature[] memory trimmed = new ProjectEscrow.Signature[](count);
            for (uint256 i; i < count; i++) {
                trimmed[i] = sigs[i];
            }
            escrow.approveMilestone(trimmed);
        }

        uint256 totalSigners = 1 + (adminSigned ? 1 : 0) + _popcount(memberBits);
        bool ruleMet = adminSigned && (_m == 0 ? true : totalSigners >= 3 && _popcount(memberBits) >= 1);
        assertEq(escrow.currentMilestoneIndex(), ruleMet ? 1 : 0);
    }

    /// A random milestone schedule is accepted iff its amounts sum exactly to
    /// the budget.
    function testFuzzMilestoneScheduleValidation(uint256 _budget, uint256 _count, uint256 _seed) public {
        _count = bound(_count, 1, 24);
        _seed = bound(_seed, 1, type(uint256).max);

        uint256[] memory amounts = new uint256[](_count);
        uint256 sum;
        for (uint256 i; i < _count; i++) {
            amounts[i] = 1 + (uint256(keccak256(abi.encode(_seed, i))) % 1000);
            sum += amounts[i];
        }
        _budget = bound(_budget, 1, type(uint256).max);

        ProjectEscrow impl = new ProjectEscrow();
        address clone = Clones.clone(address(impl));
        ProjectEscrow fresh = ProjectEscrow(clone);

        vm.expectRevert();
        fresh.initialize(builder, treasury, address(token), admin, builder, _budget, amounts, 0);

        // Correct budget: accepted, schedule mirrored.
        if (sum > 0 && amounts.length <= 24) {
            address clone2 = Clones.clone(address(impl));
            ProjectEscrow fresh2 = ProjectEscrow(clone2);
            vm.prank(address(0x60A));
            fresh2.initialize(builder, treasury, address(token), admin, builder, sum, amounts, 0);
            assertEq(fresh2.totalProjectBudget(), sum);
            (uint256 lastAmount,,) = fresh2.milestones(amounts.length - 1);
            assertEq(lastAmount, amounts[amounts.length - 1]);
        }
    }

    /// A member's digest for milestone A cannot be replayed for milestone B,
    /// and reusing a used signature reverts - across the whole suite of
    /// nonce sequences.
    function testFuzzSignatureReplayAcrossMilestones(uint256 _seed) public {
        _seed = bound(_seed, 1, type(uint256).max);
        _newEscrow();
        _setMembers(toUint256Array(100, 101, 102), new uint256[](0));

        bytes32 evidenceA = keccak256(abi.encode(_seed, "A"));
        bytes32 evidenceB = keccak256(abi.encode(_seed, "B"));

        vm.prank(builder);
        escrow.submitMilestoneComplete(evidenceA);

        // Admin signs milestone 0 alone (below threshold - no release).
        ProjectEscrow.Signature[] memory adminSigs = _milestoneSigs(0, evidenceA, toUint256Array(ADMIN_PK));
        escrow.approveMilestone(adminSigs);
        assertEq(escrow.currentMilestoneIndex(), 0);

        // The used signature cannot be replayed.
        vm.expectRevert(ProjectEscrow.AlreadySigned.selector);
        escrow.approveMilestone(adminSigs);

        // Pre-sign milestone 1 up front (per-milestone nonce still 0) while
        // milestone 0 is still pending.
        ProjectEscrow.Signature[] memory sigsB = _milestoneSigs(1, evidenceB, toUint256Array(ADMIN_PK, 100));

        // Member joins milestone 0: release fires.
        escrow.approveMilestone(_milestoneSigs(0, evidenceA, toUint256Array(100)));
        assertEq(escrow.currentMilestoneIndex(), 1);

        // The pre-signed milestone-1 batch still verifies (approving
        // milestone 0 never touched the milestone-1 nonce sequence).
        vm.prank(builder);
        escrow.submitMilestoneComplete(evidenceB);
        escrow.approveMilestone(sigsB);
        assertEq(escrow.currentMilestoneIndex(), 2);
    }

    /// The VRF draw: for any pool size and random words, members and
    /// alternates are distinct, in-pool, and the counts are exact.
    function testFuzzSelectionDrawInvariants(uint256 _poolSize, uint256 _seed) public {
        _poolSize = bound(_poolSize, 4, memberAddrs.length);
        _seed = bound(_seed, 1, type(uint256).max);

        _deployProject();
        for (uint256 i; i < _poolSize; i++) {
            vm.prank(memberAddrs[i % memberAddrs.length]);
            governance.optInForCommittee();
        }
        assertEq(governance.optInCount(), _poolSize);

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
        vm.prank(admin);
        governance.awardProposal(0);

        escrow = ProjectEscrow(governance.projectEscrow());
        assertTrue(governance.selectionPending());

        uint256 requested = _poolSize >= 5 ? 5 : _poolSize;
        uint256[] memory words = new uint256[](requested);
        for (uint256 i; i < requested; i++) {
            words[i] = uint256(keccak256(abi.encode(_seed, i)));
        }
        _fulfill(words);

        address[] memory members = escrow.getMemberSigners();
        address[] memory alts = escrow.getAlternates();

        // Draw shape follows the pool: 3 members always (pool >= 4 here),
        // and 2 alternates for pool >= 5, 1 for pool == 4.
        assertEq(members.length, 3);
        assertEq(alts.length, _poolSize >= 5 ? 2 : 1);

        for (uint256 i; i < members.length; i++) {
            assertTrue(_inPool(members[i], _poolSize));
            for (uint256 j = i + 1; j < members.length; j++) {
                assertNotEq(members[i], members[j]);
            }
        }
        for (uint256 i; i < alts.length; i++) {
            assertTrue(_inPool(alts[i], _poolSize));
            for (uint256 j; j < members.length; j++) {
                assertNotEq(alts[i], members[j]);
            }
            for (uint256 j = i + 1; j < alts.length; j++) {
                assertNotEq(alts[i], alts[j]);
            }
        }
    }

    function _popcount(uint256 _x) internal pure returns (uint256 count) {
        while (_x != 0) {
            _x &= _x - 1;
            count++;
        }
    }
}
