// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {ProjectFactory} from "../src/ProjectFactory.sol";
import {ProjectGovernance} from "../src/ProjectGovernance.sol";
import {ProjectEscrow} from "../src/ProjectEscrow.sol";
import {PaymentToken} from "../src/PaymentToken.sol";
import {CompanyRegistry} from "../src/CompanyRegistry.sol";
import {Redemption} from "../src/Redemption.sol";
import {IProjectConfig} from "../src/Interfaces/IProjectConfig.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

/// @title TestBase
/// @notice Shared deployment + signing fixtures for the DemocraFund test
///         suites. Deploys the full stack (token, registry, factory, VRF
///         mock, redemption) and exposes helpers for EIP-712 signing,
///         direct escrow deployment, and full lifecycle walks.
/// @dev Uses fixed private keys (ADMIN_PK = 1, BUILDER_PK = 2, members 100+)
///      so signatures are reproducible via vm.sign over the escrow's digest
///      getters. Note: helper functions that make view calls (digest getters,
///      selectionRequestId) consume vm.expectRevert - compute into locals first.
contract TestBase is Test {
    ProjectFactory factory;
    ProjectGovernance governance;
    ProjectEscrow escrow;
    PaymentToken token;
    CompanyRegistry registry;
    Redemption redemption;
    VRFCoordinatorV2_5Mock vrf;
    uint256 subscriptionId;

    // Governance address used as the escrow's controller in direct unit tests.
    address gov = address(0x60A);

    uint256 constant ADMIN_PK = 1;
    uint256 constant BUILDER_PK = 2;
    uint256 constant TREASURY_PK = 3;
    uint256 constant CREATOR_PK = 4;
    uint256 constant OUTSIDER_PK = 5;
    uint256 constant PAYMENT_PK = 6;

    address admin = vm.addr(ADMIN_PK);
    address builder = vm.addr(BUILDER_PK);
    address treasury = vm.addr(TREASURY_PK);
    address creator = vm.addr(CREATOR_PK);
    address outsider = vm.addr(OUTSIDER_PK);
    address paymentWallet = vm.addr(PAYMENT_PK);

    uint256[] memberPks = [100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111];
    address[] memberAddrs;
    mapping(address => uint256) pkOf;

    uint256 constant BUDGET_CAP = 5000;
    uint256 constant COST = 1000;
    uint256 constant COMMITTEE_FEE = 10;
    uint256 constant COMPANY_ID = 1; // builder's registered company.
    /// forge-lint: disable-next-line(mixed-case-variable) // Fixture constants.
    uint256[3] AMOUNTS = [uint256(300), uint256(300), uint256(400)];
    /// forge-lint: disable-next-line(mixed-case-variable) // Fixture constants.
    bytes32 EVIDENCE = keccak256("evidence");

    event MilestoneApproved(uint256 indexed milestoneIndex, address indexed signer);
    event MilestoneReleased(uint256 indexed milestoneIndex, address indexed projectWallet, uint256 amount);
    event CancellationApproved(address indexed signer, bytes32 reasonHash);
    event ProjectTerminated(address indexed treasuryWallet, uint256 returnedAmount);

    function setUp() public virtual {
        for (uint256 i; i < memberPks.length; i++) {
            address m = vm.addr(memberPks[i]);
            memberAddrs.push(m);
            pkOf[m] = memberPks[i];
        }

        token = new PaymentToken(address(this));
        ProjectEscrow escrowImpl = new ProjectEscrow();
        vrf = new VRFCoordinatorV2_5Mock(0, 0, 1);

        subscriptionId = vrf.createSubscription();
        vrf.fundSubscription(subscriptionId, 1e24);

        IProjectConfig.VRFConfig memory vrfConfig = IProjectConfig.VRFConfig({
            coordinator: address(vrf),
            subscriptionId: subscriptionId,
            keyHash: bytes32(uint256(1)),
            callbackGasLimit: 500_000,
            requestConfirmations: 3,
            nativePayment: false
        });

        registry = new CompanyRegistry();
        vm.prank(builder);
        registry.registerCompany(builder, keccak256("builder company info"));

        factory = new ProjectFactory(
            1 weeks, 1 weeks, 1 weeks, address(token), address(escrowImpl), creator, address(registry), vrfConfig
        );
        token.setFactoryRole(address(factory));
        token.setFactoryRole(address(this));

        // Off-ramp: the test contract plays the paying authority.
        redemption = new Redemption(address(token), address(this));
        token.setFactoryRole(address(redemption));
    }

    // --------------------------------------------------------------------------
    // ----------------------------------- HELPERS -------------------------------
    // --------------------------------------------------------------------------

    /// @notice Standard tender config: 8-day proposal window, 16-day voting
    ///         window, budget cap 5000, admin as the governance safe wallet.
    function _projectConfig() internal view returns (IProjectConfig.ProjectConfig memory cfg) {
        cfg = IProjectConfig.ProjectConfig({
            budgetCap: BUDGET_CAP,
            committeeFeePerSignature: COMMITTEE_FEE,
            proposalDeadline: uint64(block.timestamp + 8 days),
            votingDeadline: uint64(block.timestamp + 16 days),
            deliberationWindow: 7 days,
            governanceSafeWallet: admin,
            title: keccak256("Entrance Upgrade"),
            category: keccak256("Clubhouse"),
            department: keccak256("Clubhouse"),
            specContentHash: keccak256("spec"),
            ipfsHash: keccak256("ipfs"),
            treasuryWallet: treasury
        });
    }

    /// @notice Milestone amounts summing to COST (300 + 300 + 400), as a raw
    ///         uint256 array for direct escrow initialization.
    function _milestoneAmounts() internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](3);
        amounts[0] = 300;
        amounts[1] = 300;
        amounts[2] = 400;
    }

    /// @notice The same schedule as _milestoneAmounts, shaped as governance
    ///         Milestone structs for createProposal.
    function _proposalMilestones() internal pure returns (ProjectGovernance.Milestone[] memory milestones) {
        milestones = new ProjectGovernance.Milestone[](3);
        milestones[0] = ProjectGovernance.Milestone(300, bytes32(0), false);
        milestones[1] = ProjectGovernance.Milestone(300, bytes32(0), false);
        milestones[2] = ProjectGovernance.Milestone(400, bytes32(0), false);
    }

    /// Walks a full lifecycle: create -> proposals -> voting -> award.
    /// Opt-ins happen during PROPOSAL. Returns the deployed escrow.
    function _deployAndAward(uint256 _optInCount) internal returns (ProjectEscrow) {
        _deployProject();

        for (uint256 i; i < _optInCount; i++) {
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

        vm.prank(memberAddrs[0]);
        governance.voteForProposal(0);

        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        governance.closeVoting(5);

        vm.prank(admin);
        governance.awardProposal(0);

        escrow = ProjectEscrow(governance.projectEscrow());
        return escrow;
    }

    /// Deploys a fresh project via the factory and opens proposals.
    function _deployProject() internal {
        vm.prank(creator);
        address governanceAddr = factory.createProject(_projectConfig());
        governance = ProjectGovernance(governanceAddr);

        // Register this project as a VRF consumer on the shared subscription,
        // mirroring the production setup step.
        vrf.addConsumer(subscriptionId, governanceAddr);

        vm.prank(admin);
        governance.acceptProposals();
    }

    /// Direct escrow deployment for granular unit tests (controller = gov).
    function _newEscrow() internal returns (ProjectEscrow) {
        ProjectEscrow impl = new ProjectEscrow();
        address clone = Clones.clone(address(impl));
        escrow = ProjectEscrow(clone);

        // The direct escrows use a dummy fee payer instead of a real
        // governance contract: the fee forwarding path (escrow -> governance
        // -> factory -> token) is exercised end-to-end in the integration
        // tests, where the real governance contract exists.
        gov = address(new DummyGovernance());

        vm.prank(gov);
        escrow.initialize(builder, treasury, address(token), admin, builder, COST, _milestoneAmounts(), COMMITTEE_FEE);

        // Mirror production funding: budget plus the committee fee reserve.
        token.mint(address(escrow), COST + escrow.feeReserve());
        return escrow;
    }

    /// @notice Finalises a direct escrow's committee from private keys.
    function _setMembers(uint256[] memory _memberPks, uint256[] memory _altPks) internal {
        address[] memory members = new address[](_memberPks.length);
        for (uint256 i; i < _memberPks.length; i++) {
            members[i] = vm.addr(_memberPks[i]);
        }
        address[] memory alts = new address[](_altPks.length);
        for (uint256 i; i < _altPks.length; i++) {
            alts[i] = vm.addr(_altPks[i]);
        }

        vm.prank(gov);
        escrow.setCommitteeMembers(members, alts);
    }

    /// @notice Signs a digest with a known private key and packs (r, s, v).
    function _sign(uint256 _pk, bytes32 _digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pk, _digest);
        return abi.encodePacked(r, s, v);
    }

    /// @notice Builds EIP-712 milestone approval signatures for the given private
    ///         keys, using the escrow's own digest getter (which embeds each
    ///         signer's current nonce).
    function _milestoneSigs(uint256 _index, bytes32 _evidence, uint256[] memory _pks)
        internal
        returns (ProjectEscrow.Signature[] memory sigs)
    {
        sigs = new ProjectEscrow.Signature[](_pks.length);
        for (uint256 i; i < _pks.length; i++) {
            address signer = vm.addr(_pks[i]);
            bytes32 digest = escrow.getMilestoneApprovalDigest(_index, _evidence, signer);
            sigs[i] = ProjectEscrow.Signature({signer: signer, signature: _sign(_pks[i], digest)});
        }
    }

    /// @notice Builds EIP-712 cancellation approval signatures for the given
    ///         private keys, all committing to the same reason hash.
    function _cancellationSigs(bytes32 _reason, uint256[] memory _pks)
        internal
        returns (ProjectEscrow.Signature[] memory sigs)
    {
        sigs = new ProjectEscrow.Signature[](_pks.length);
        for (uint256 i; i < _pks.length; i++) {
            address signer = vm.addr(_pks[i]);
            bytes32 digest = escrow.getCancellationApprovalDigest(_reason, signer);
            sigs[i] = ProjectEscrow.Signature({signer: signer, signature: _sign(_pks[i], digest)});
        }
    }

    /// @notice Drives the official mock coordinator's fulfillment callback for the
    ///         in-flight selection request with the given random words.
    function _fulfill(uint256[] memory _words) internal {
        vrf.fulfillRandomWordsWithOverride(governance.selectionRequestId(), address(governance), _words);
    }

    /// @notice Deterministic pseudo-random words for deterministic draws.
    function _wordsFrom(uint256 _seed, uint256 _count) internal pure returns (uint256[] memory words) {
        words = new uint256[](_count);
        for (uint256 i; i < _count; i++) {
            words[i] = uint256(keccak256(abi.encode(_seed, i)));
        }
    }

    function _inPool(address _a, uint256 _poolSize) internal view returns (bool) {
        for (uint256 i; i < _poolSize; i++) {
            if (_a == memberAddrs[i]) return true;
        }
        return false;
    }

    function toUint256Array(uint256 a) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = a;
    }

    function toUint256Array(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function toUint256Array(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function toUint256Array(uint256 a, uint256 b, uint256 c, uint256 d) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](4);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
        arr[3] = d;
    }
}

/// @notice Stand-in for ProjectGovernance as the direct escrow's controller
///         (the address that calls initialize/abort/releaseSettlement).
///         The real governance -> escrow relationship is covered end-to-end
///         by the integration tests.
contract DummyGovernance {
    function setCommitteeMembers(address[] calldata, address[] calldata) external {}
}

/// @notice Minimal ERC-1271 smart wallet: verifies signatures by ecrecover
///         against a fixed owner key. Used to prove the escrow's
///         SignatureChecker path works for account-abstraction-style wallets.
contract MockERC1271Wallet {
    address public immutable OWNER;

    constructor(address _owner) {
        OWNER = _owner;
    }

    function isValidSignature(bytes32 _hash, bytes memory _signature) external view returns (bytes4) {
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(_signature, (uint8, bytes32, bytes32));
        if (ecrecover(_hash, v, r, s) == OWNER) return this.isValidSignature.selector;
        return 0xffffffff;
    }
}
