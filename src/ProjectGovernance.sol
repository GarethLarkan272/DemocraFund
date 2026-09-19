// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ProjectEscrow} from "./ProjectEscrow.sol";
import {ProjectFactory} from "./ProjectFactory.sol";
import {CompanyRegistry} from "./CompanyRegistry.sol";
import {IProjectConfig} from "./Interfaces/IProjectConfig.sol";

/// @title ProjectGovernance
/// @notice Per-project lifecycle controller: tendering, proposal submission,
///         citizen voting, award and committee selection via Chainlink VRF v2.5.
///
///         Committee selection: members opt in during PROPOSAL/VOTING/
///         DELIBERATION. On award, the pool decides the committee shape:
///           - 0 opt-ins: 2-of-2 admin+builder escrow (no community)
///           - 1-3 opt-ins: everyone serves, no randomness needed
///           - 4+ opt-ins: VRF draw of 3 members + 2 alternates
///
///         Uses the official Chainlink VRFConsumerBaseV2Plus: the coordinator
///         calls rawFulfillRandomWords and this contract overrides
///         fulfillRandomWords to perform the draw. Because the consumer base
///         requires its coordinator in the constructor, each governance
///         contract is deployed directly by the factory (not cloned) - the
///         escrow below it still uses clones.
/// @dev Governance tracks the lifecycle state machine and committee selection
///      ONLY. All milestone and fund logic lives in ProjectEscrow, which is
///      the source of truth for releases; Proposal.milestones here mirrors it
///      for history.
contract ProjectGovernance is VRFConsumerBaseV2Plus, AccessControl {
    using Clones for address;

    enum PROJECT_LIFECYCLE {
        CREATED,
        PROPOSAL,
        VOTING,
        DELIBERATION,
        AWARDED,
        COMPLETE,
        CANCELLED
    }

    struct Proposal {
        uint256 id;
        uint256 cost;
        address admin;
        address fundWallet;
        bytes32 specContentHash;
        bytes32 ipfsHash;
        bool depositRequired;
        Milestone[] milestones;
    }

    struct Milestone {
        uint256 amount;
        bytes32 evidenceHash;
        bool released;
    }

    // --------------------------------------------------------------------------
    // ----------------------------------------> STORAGE <-----------------------
    // --------------------------------------------------------------------------
    //
    // Slot 1 (26 of 32 bytes used): lifecycle state + deadlines + VRF lane.
    PROJECT_LIFECYCLE public projectLifecycle; // 1 byte.
    PROJECT_LIFECYCLE public cancelledForm; // 1 byte; non-default so the lifecycle can never default to CREATED.
    uint64 public proposalDeadline; // 8 bytes; proposals close here.
    uint64 public votingDeadline; // 8 bytes; voting closes here - time-enforced.
    uint32 public callbackGasLimit; // 4 bytes; VRF fulfillment gas cap.
    uint16 public requestConfirmations; // 2 bytes; VRF block confirmations.
    bool public nativePayment; // 1 byte; true = pay VRF in native ETH.
    bool public selectionPending; // 1 byte; true between VRF request and fulfillment.

    // Wallets / contracts - 20 bytes each, one per slot.
    address public token; // The payment token funded into escrows.
    address public projectGovernanceSafeWallet; // The admin (DEFAULT_ADMIN_ROLE holder).
    address public treasuryWallet; // Receives refunded funds on cancellation.
    address public projectEscrowImplementation; // The escrow clone implementation.
    ProjectFactory public projectFactory; // The deploying factory.
    ProjectEscrow public projectEscrow; // The live escrow for this project.
    CompanyRegistry public companyRegistry; // Companies allowed to bid.

    // Counters and amounts - 32 bytes each, one per slot.
    // The contract address itself is the project ID (unique, derivation-resistant).
    uint256 public winningProposalId;
    uint256 public budgetCap;
    uint256 public numberOfProposals;
    uint256 public numberOfShortlistedProjects;
    uint256 public numberOfTotalMilestones;
    uint256 public subscriptionId; // VRF v2.5 subscription funding this project.
    uint256 public optInCount; // Size of the committee opt-in pool.
    uint256 public selectionRequestId; // The in-flight VRF request.
    uint256 public committeeFeePerSignature; // Minted per member per milestone signed.
    uint256 public awardDeadline; // Last moment the admin may award; then anyone can expire.
    uint256 public selectionRequestedAt; // When the draw was requested; enables permissionless retry.

    // Content hashes - 32 bytes each, one per slot. deliberationWindow is a
    // lone 8-byte value that cannot pack into slot 1 (26 of 32 bytes used),
    // so it sits on its own slot here.
    bytes32 public category;
    bytes32 public department;
    bytes32 public title;
    bytes32 public specContentHash; // Kept for on-chain verification of the tender.
    bytes32 public ipfsHash; // Tender documents.
    bytes32 public keyHash; // VRF gas lane.
    uint64 public deliberationWindow; // Award window after voting closes.

    // Vote storage.
    mapping(uint256 proposalCount => Proposal proposalInformation) public proposals;
    mapping(uint256 proposalId => uint256 proposalVotes) public numberOfVotesPerProposal;
    mapping(address user => bool voted) public hasVoted;

    // Committee opt-in pool - ids are contiguous, so optedInById[pick] indexes
    // exactly like an array would, without storing a full array.
    mapping(address => bool) public optedIn;
    mapping(uint256 id => address member) public optedInById;

    // One proposal per company per tender.
    mapping(uint256 companyId => bool submitted) public companyHasProposal;

    // Committee draw output (mirrors the escrow's signers for off-chain reads).
    address[] public committeeMembers;
    address[] public alternates;

    uint256 public constant MAX_COMMITTEE_MEMBERS = 3;
    uint256 public constant MAX_ALTERNATES = 2;
    uint256 public constant MAX_MILESTONES = 24;
    uint256 public constant SELECTION_RETRY_DELAY = 7 days; // After this, anyone may re-request or abort a pending draw.
    uint256 public constant MAX_COMMITTEE_FEE_PER_SIGNATURE = 1000; // Mirrors ProjectFactory's cap (defense in depth).

    // --------------------------------------------------------------------------
    // -----------------------------------> ERRORS / EVENTS <---------------------
    // --------------------------------------------------------------------------

    error InvalidProjectLifecycle();
    error UserAlreadyVoted();
    error VotingStillOpen();
    error VotingClosed();
    error ProposalsDurationTooShort();
    error ZeroAmount();
    error BudgetTooHigh();
    error AddressZero();
    error MilestonesDontMatchCost();
    error ProposalDeadlinePassed();
    error InvalidMilestoneCount();
    error InvalidHash();
    error ProposalNonExistent();
    error MilestoneReleased();
    error MilestonesNotAllReleased();
    error EscrowNotCancelled();
    error AlreadyOptedIn();
    error AdminCannotOptIn();
    error OptInClosed();
    error SelectionNotPending();
    error InvalidRequestId();
    error InsufficientRandomWords();
    error UnauthorisedCalled();
    error NotInShortlist();
    error AwardDeadlinePassed();
    error AlreadySubmittedProposal();
    error CompanyNotActive();

    event VoteCast(address indexed voter, uint256 indexed proposalId);
    event CommitteeOptIn(address indexed member);
    event CommitteeSelectionRequested(uint256 indexed requestId, uint256 poolSize);
    event CommitteeSelected(address[] members, address[] alternates);
    event ProjectLifecycleChanged(PROJECT_LIFECYCLE indexed from, PROJECT_LIFECYCLE indexed to);
    event ProposalCreated(
        uint256 indexed proposalId, uint256 indexed companyId, address indexed companyAdmin, uint256 cost
    );
    event ProposalAwarded(uint256 indexed proposalId, address indexed escrow, uint256 cost);

    /// @notice Deploys a project's governance contract.
    /// @param _config The tender configuration (budget, deadlines, content).
    /// @param _vrf Coordinator + subscription + gas lane configuration.
    /// @param _projectEscrowImplementation The escrow implementation that
    ///        awardProposal clones per project.
    /// @param _paymentToken The payment token funded into escrows.
    /// @param _companyRegistry Companies allowed to submit proposals.
    /// @dev Called by the factory, so msg.sender becomes projectFactory.
    ///      DEFAULT_ADMIN_ROLE is granted to the governance safe wallet. The
    ///      coordinator address is stored by VRFConsumerBaseV2Plus.
    constructor(
        IProjectConfig.ProjectConfig memory _config,
        IProjectConfig.VRFConfig memory _vrf,
        address _projectEscrowImplementation,
        address _paymentToken,
        address _companyRegistry
    ) VRFConsumerBaseV2Plus(_vrf.coordinator) {
        if (_config.treasuryWallet == address(0)) revert AddressZero();
        if (_paymentToken == address(0)) revert AddressZero();
        if (_companyRegistry == address(0)) revert AddressZero();
        if (_config.committeeFeePerSignature > MAX_COMMITTEE_FEE_PER_SIGNATURE) revert ZeroAmount();
        if (_vrf.subscriptionId == 0) revert ZeroAmount();
        if (_vrf.keyHash == bytes32(0)) revert InvalidHash();
        if (_vrf.callbackGasLimit == 0) revert ZeroAmount();

        budgetCap = _config.budgetCap;
        committeeFeePerSignature = _config.committeeFeePerSignature;
        proposalDeadline = _config.proposalDeadline;
        votingDeadline = _config.votingDeadline;
        deliberationWindow = _config.deliberationWindow;
        projectEscrowImplementation = _projectEscrowImplementation;
        title = _config.title;
        category = _config.category;
        department = _config.department;
        specContentHash = _config.specContentHash;
        ipfsHash = _config.ipfsHash;

        token = _paymentToken;
        treasuryWallet = _config.treasuryWallet;

        subscriptionId = _vrf.subscriptionId;
        keyHash = _vrf.keyHash;
        callbackGasLimit = _vrf.callbackGasLimit;
        requestConfirmations = _vrf.requestConfirmations;
        nativePayment = _vrf.nativePayment;

        projectFactory = ProjectFactory(msg.sender);
        projectGovernanceSafeWallet = _config.governanceSafeWallet;
        companyRegistry = CompanyRegistry(_companyRegistry);

        // Set to CANCELLED so the lifecycle can never default to CREATED.
        cancelledForm = PROJECT_LIFECYCLE.CANCELLED;

        _grantRole(DEFAULT_ADMIN_ROLE, _config.governanceSafeWallet);
    }

    // --------------------------------------------------------------------------
    // ----------------------------------> LIFECYCLE CHANGE FUNCTIONS <-----------
    // --------------------------------------------------------------------------

    /// @notice Opens the proposal window.
    /// @dev CREATED -> PROPOSAL. Admin only.
    function acceptProposals() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (projectLifecycle != PROJECT_LIFECYCLE.CREATED) revert InvalidProjectLifecycle();

        projectLifecycle = PROJECT_LIFECYCLE.PROPOSAL;
        emit ProjectLifecycleChanged(PROJECT_LIFECYCLE.CREATED, PROJECT_LIFECYCLE.PROPOSAL);
    }

    /// @notice Closes proposals and opens voting.
    /// @dev PROPOSAL -> VOTING. Admin only, and only once the proposal deadline
    ///      has passed - the window length is enforced, not advisory.
    function closeProposalsAndOpenVoting() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (projectLifecycle != PROJECT_LIFECYCLE.PROPOSAL) revert InvalidProjectLifecycle();
        if (block.timestamp < proposalDeadline) revert ProposalsDurationTooShort();

        projectLifecycle = PROJECT_LIFECYCLE.VOTING;
        emit ProjectLifecycleChanged(PROJECT_LIFECYCLE.PROPOSAL, PROJECT_LIFECYCLE.VOTING);
    }

    /// @notice Closes voting and moves to deliberation.
    /// @param _numberOfShortlistedProjects How many top proposals the committee
    ///        will deliberate over (visible to the public for transparency).
    /// @dev VOTING -> DELIBERATION. Admin only. Voting closes by time, not by
    ///      admin whim - the deadline was fixed at creation.
    function closeVoting(uint256 _numberOfShortlistedProjects) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_numberOfShortlistedProjects == 0) revert ZeroAmount();
        if (projectLifecycle != PROJECT_LIFECYCLE.VOTING) revert InvalidProjectLifecycle();
        if (block.timestamp < votingDeadline) revert VotingStillOpen();

        projectLifecycle = PROJECT_LIFECYCLE.DELIBERATION;
        numberOfShortlistedProjects = _numberOfShortlistedProjects;
        awardDeadline = block.timestamp + deliberationWindow;
        emit ProjectLifecycleChanged(PROJECT_LIFECYCLE.VOTING, PROJECT_LIFECYCLE.DELIBERATION);
    }

    /// @notice Awards the winning proposal and instantiates the project escrow.
    /// @param _proposalId The proposal being awarded (admin's choice from the
    ///        shortlist - off-list choices remain visible and auditable).
    /// @return projectEscrowInstanceAddr The deployed escrow clone.
    /// @dev DELIBERATION -> AWARDED. Admin only, and only until awardDeadline
    ///      (afterwards expireDeliberation lets anyone cancel the tender).
    ///      The award is bound to the votes: the proposal must be inside the
    ///      top numberOfShortlistedProjects by vote count, so the admin can
    ///      choose among the shortlist but cannot award a loser. Deploys +
    ///      funds the escrow, then shapes the committee from the opt-in pool:
    ///        - pool 0: escrow finalised with no members (2-of-2 fallback)
    ///        - pool 1-3: everyone serves, no randomness needed
    ///        - pool 4+: a VRF request is fired inside this transaction and
    ///          the escrow stays unfinalised until the coordinator responds.
    ///      The committee is NEVER supplied by the admin - it comes only from
    ///      the pool. A requested deposit (first milestone) is released here.
    function awardProposal(uint256 _proposalId)
        external
        proposalExists(_proposalId)
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (address projectEscrowInstanceAddr)
    {
        Proposal memory tempProposal = proposals[_proposalId];
        if (projectLifecycle != PROJECT_LIFECYCLE.DELIBERATION) revert InvalidProjectLifecycle();
        if (block.timestamp > awardDeadline) revert AwardDeadlinePassed();
        _requireInShortlist(_proposalId);
        winningProposalId = _proposalId;
        projectLifecycle = PROJECT_LIFECYCLE.AWARDED;
        emit ProjectLifecycleChanged(PROJECT_LIFECYCLE.DELIBERATION, PROJECT_LIFECYCLE.AWARDED);

        uint256[] memory milestoneAmounts = new uint256[](tempProposal.milestones.length);
        for (uint256 x; x < tempProposal.milestones.length; x++) {
            milestoneAmounts[x] = tempProposal.milestones[x].amount;
        }

        projectEscrowInstanceAddr = projectEscrowImplementation.clone();
        projectEscrow = ProjectEscrow(projectEscrowInstanceAddr);
        projectEscrow.initialize(
            tempProposal.fundWallet,
            treasuryWallet,
            token,
            projectGovernanceSafeWallet,
            tempProposal.fundWallet,
            tempProposal.cost,
            milestoneAmounts,
            committeeFeePerSignature
        );

        numberOfTotalMilestones += tempProposal.milestones.length;

        // Fund the escrow with the awarded budget PLUS the committee fee
        // reserve (the escrow computes and exposes it; it is bounded by the
        // fee cap and milestone count). The reserve is what members pull
        // their fees from via collectFees().
        projectFactory.mintInitialSupplyForProject(
            projectEscrowInstanceAddr, tempProposal.cost + projectEscrow.feeReserve()
        );

        uint256 poolSize = optInCount;

        if (poolSize == 0) {
            // No community committee opted in: 2-of-2 admin + builder escrow.
            projectEscrow.setCommitteeMembers(new address[](0), new address[](0));
        } else if (poolSize <= MAX_COMMITTEE_MEMBERS) {
            // Pool too small for a meaningful draw: everyone serves.
            address[] memory members = _allOptedIn();
            projectEscrow.setCommitteeMembers(members, new address[](0));
        } else {
            // Pool big enough: random draw via Chainlink VRF.
            _requestCommitteeSelection();
        }

        if (proposals[_proposalId].depositRequired) {
            projectEscrow.releaseDeposit();
        }

        emit ProposalAwarded(_proposalId, projectEscrowInstanceAddr, tempProposal.cost);
    }

    /// @notice Marks the project complete once every milestone is released.
    /// @dev Permissionless: the escrow's release history IS the proof, so no
    ///      admin is needed to close the book. Sweeps the un-owed fee
    ///      reserve to the treasury as part of completion - the fee
    ///      liability is final once every milestone has released.
    function completeProject() external {
        if (projectLifecycle != PROJECT_LIFECYCLE.AWARDED) revert InvalidProjectLifecycle();
        if (!projectEscrow.allMilestonesReleased()) revert MilestonesNotAllReleased();

        projectEscrow.sweepSurplusToTreasury();

        projectLifecycle = PROJECT_LIFECYCLE.COMPLETE;
        emit ProjectLifecycleChanged(PROJECT_LIFECYCLE.AWARDED, PROJECT_LIFECYCLE.COMPLETE);
    }

    /// @notice Cancels a tender the admin never awarded in time.
    /// @dev Permissionless, once awardDeadline has passed. Nothing has been
    ///      funded or deployed yet (the escrow only exists after award), so
    ///      this is pure lifecycle cleanup - it guarantees the deliberation
    ///      phase cannot stall forever on a missing admin.
    function expireDeliberation() external {
        if (projectLifecycle != PROJECT_LIFECYCLE.DELIBERATION) revert InvalidProjectLifecycle();
        if (block.timestamp <= awardDeadline) revert VotingStillOpen();

        cancelledForm = projectLifecycle;
        projectLifecycle = PROJECT_LIFECYCLE.CANCELLED;
        emit ProjectLifecycleChanged(cancelledForm, PROJECT_LIFECYCLE.CANCELLED);
    }

    /// @notice Cancels the project at any stage.
    /// @dev Three paths:
    ///        - Pre-award: admin alone can cancel (no funds at stake yet).
    ///        - Post-award, committee draw pending: admin alone may abort
    ///          immediately; once SELECTION_RETRY_DELAY has passed since the
    ///          request, anyone may abort - the funds are returned to the
    ///          treasury so a vanished admin cannot lock them forever.
    ///        - Post-award, committee finalised: the escrow's 4-of-5 (derived)
    ///          cancellation must have already fired; anyone can then finalise
    ///          the lifecycle here - the signatures are the on-chain proof.
    function cancelProject() external {
        if (projectLifecycle == PROJECT_LIFECYCLE.CANCELLED || projectLifecycle == PROJECT_LIFECYCLE.COMPLETE) {
            revert InvalidProjectLifecycle();
        }

        if (projectLifecycle == PROJECT_LIFECYCLE.AWARDED) {
            if (!projectEscrow.committeeFinalized()) {
                _authorizePendingDrawAbort();
                projectEscrow.abort();
            } else if (!projectEscrow.cancelled()) {
                revert EscrowNotCancelled();
            }
        } else {
            _checkRole(DEFAULT_ADMIN_ROLE);
        }

        cancelledForm = projectLifecycle;
        projectLifecycle = PROJECT_LIFECYCLE.CANCELLED;
        emit ProjectLifecycleChanged(cancelledForm, PROJECT_LIFECYCLE.CANCELLED);
    }

    /// @dev Admin can abort a pending draw immediately; after
    ///      SELECTION_RETRY_DELAY anyone can - the draw is stuck and the
    ///      funds must not be locked behind one wallet.
    function _authorizePendingDrawAbort() internal view {
        if (selectionRequestedAt == 0) {
            _checkRole(DEFAULT_ADMIN_ROLE);
            return;
        }
        if (block.timestamp < selectionRequestedAt + SELECTION_RETRY_DELAY) {
            _checkRole(DEFAULT_ADMIN_ROLE);
        }
    }

    /// @notice Pays a partial settlement to the builder from the escrow.
    /// @param _settlementAmount Amount to pay before a cancellation finalises.
    /// @dev Admin only; forwarded to the escrow, which enforces the cap
    ///      (settlements can never dip into outstanding fee credits).
    function releaseSettlement(uint256 _settlementAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (projectLifecycle != PROJECT_LIFECYCLE.AWARDED) revert InvalidProjectLifecycle();
        projectEscrow.releaseSettlement(_settlementAmount);
    }

    // --------------------------------------------------------------------------
    // ---------------------------------> COMMITTEE OPT-IN & SELECTION <----------
    // --------------------------------------------------------------------------

    /// @notice Opts the caller in to the milestone-approval committee pool.
    /// @dev Open while the tender is live (PROPOSAL through DELIBERATION).
    ///      One member, one opt-in. The admin cannot opt in - they are a
    ///      signer regardless.
    function optInForCommittee() external {
        if (
            projectLifecycle != PROJECT_LIFECYCLE.PROPOSAL && projectLifecycle != PROJECT_LIFECYCLE.VOTING
                && projectLifecycle != PROJECT_LIFECYCLE.DELIBERATION
        ) revert OptInClosed();
        if (msg.sender == projectGovernanceSafeWallet) revert AdminCannotOptIn();
        if (optedIn[msg.sender]) revert AlreadyOptedIn();

        optedIn[msg.sender] = true;
        optedInById[optInCount] = msg.sender;
        optInCount++;

        emit CommitteeOptIn(msg.sender);
    }

    /// @notice VRF coordinator callback (official VRFConsumerBaseV2Plus flow:
    ///         rawFulfillRandomWords verifies the caller, then calls this).
    /// @param _requestId Must match the in-flight selectionRequestId.
    /// @param _randomWords One word per pick (3 members + up to 2 alternates).
    /// @dev Kept deliberately light so it can never exceed the callback gas
    ///      limit: it only derives the committee and finalises the escrow.
    function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override {
        if (_requestId != selectionRequestId) revert InvalidRequestId();
        if (!selectionPending) revert SelectionNotPending();

        _selectCommittee(_randomWords);
        selectionPending = false;

        emit CommitteeSelected(committeeMembers, alternates);
    }

    /// @dev Fires a VRF request for the committee draw. One word per pick:
    ///      5 words for a full committee (3 + 2 alternates), fewer if the pool
    ///      is small. Requires the subscription to be funded and this project
    ///      to be registered as a consumer.
    function _requestCommitteeSelection() internal {
        uint256 poolSize = optInCount;

        uint32 numWords = poolSize >= MAX_COMMITTEE_MEMBERS + MAX_ALTERNATES
            ? uint32(MAX_COMMITTEE_MEMBERS + MAX_ALTERNATES)
            : uint32(poolSize);

        selectionRequestId = IVRFCoordinatorV2Plus(address(s_vrfCoordinator)).requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: nativePayment}))
            })
        );
        selectionPending = true;
        selectionRequestedAt = block.timestamp;

        emit CommitteeSelectionRequested(selectionRequestId, poolSize);
    }

    /// @notice Re-requests randomness if the original request was never
    ///         fulfilled (e.g. subscription underfunded, coordinator hiccup).
    /// @dev Admin may retry immediately; once SELECTION_RETRY_DELAY has
    ///      passed, anyone may - the old requestId is simply superseded.
    function retryCommitteeSelection() external {
        if (!selectionPending) revert SelectionNotPending();
        if (msg.sender != projectGovernanceSafeWallet) {
            if (selectionRequestedAt == 0 || block.timestamp < selectionRequestedAt + SELECTION_RETRY_DELAY) {
                _checkRole(DEFAULT_ADMIN_ROLE);
            }
        }
        _requestCommitteeSelection();
    }

    /// @dev Performs the draw: picks memberCount + alternateCount distinct
    ///      indexes from the opt-in pool, collision-safe, then finalises the
    ///      escrow's committee.
    function _selectCommittee(uint256[] calldata _randomWords) internal {
        uint256 poolSize = optInCount;
        uint256 memberCount = poolSize >= MAX_COMMITTEE_MEMBERS ? MAX_COMMITTEE_MEMBERS : poolSize;
        uint256 alternateCount =
            poolSize >= MAX_COMMITTEE_MEMBERS + MAX_ALTERNATES ? MAX_ALTERNATES : poolSize - memberCount;

        if (_randomWords.length < memberCount + alternateCount) revert InsufficientRandomWords();

        committeeMembers = new address[](memberCount);
        alternates = new address[](alternateCount);

        bool[] memory used = new bool[](poolSize);
        for (uint256 i; i < memberCount + alternateCount; i++) {
            uint256 pick = _collisionSafePick(_randomWords[i], poolSize, used);
            used[pick] = true;

            if (i < memberCount) {
                committeeMembers[i] = optedInById[pick];
            } else {
                alternates[i - memberCount] = optedInById[pick];
            }
        }

        projectEscrow.setCommitteeMembers(committeeMembers, alternates);
    }

    /// @dev index = word % poolSize, re-deriving from the word on collision
    ///      until a free index is found. Bounded in practice: each pick leaves
    ///      at least one index unused, and picks never exceed the pool size.
    function _collisionSafePick(uint256 _word, uint256 _poolSize, bool[] memory _used)
        internal
        pure
        returns (uint256)
    {
        uint256 index = _word % _poolSize;
        uint256 attempt;
        while (_used[index]) {
            attempt++;
            index = uint256(keccak256(abi.encode(_word, attempt))) % _poolSize;
        }
        return index;
    }

    /// @dev Materialises the full opt-in pool (ids are contiguous, so the
    ///      mapping is equivalent to a packed array). Only used when the pool
    ///      is small enough that everyone serves directly.
    function _allOptedIn() internal view returns (address[] memory members) {
        members = new address[](optInCount);
        for (uint256 i; i < optInCount; i++) {
            members[i] = optedInById[i];
        }
    }

    /// @dev Binds the award to the votes: reverts unless the proposal is
    ///      among the top numberOfShortlistedProjects by vote count. The
    ///      check counts proposals with strictly more votes, so boundary
    ///      ties all pass (a shortlist of 5 with 8 tied leaders admits all 8).
    function _requireInShortlist(uint256 _proposalId) internal view {
        uint256 votes = numberOfVotesPerProposal[_proposalId];
        uint256 strictlyMore;
        for (uint256 i; i < numberOfProposals; i++) {
            if (numberOfVotesPerProposal[i] > votes) strictlyMore++;
        }
        if (strictlyMore >= numberOfShortlistedProjects) revert NotInShortlist();
    }

    // --------------------------------------------------------------------------
    // ------------------------------------------> PROPOSALS <-------------------
    // --------------------------------------------------------------------------

    /// @notice Submits a proposal (bid) for the tender on behalf of a company.
    /// @param _companyId The bidding company (see CompanyRegistry); its admin
    ///        wallet must be the caller and its payment wallet becomes the
    ///        proposal's fund wallet.
    /// @param _specContentHash The proposal's specification content.
    /// @param _ipfsHash The proposal's supporting documents.
    /// @param _cost Total bid price; must equal the sum of all milestone
    ///        amounts and must not exceed the budget cap.
    /// @param _depositRequired Whether the first milestone is released
    ///        automatically on award (the deposit).
    /// @param _milestones The payment schedule, 2-24 milestones, each with a
    ///        non-zero amount.
    /// @dev Open during PROPOSAL only, until the proposal deadline. Only a
    ///      registered and active company's admin wallet may bid, and only
    ///      once per tender; the company's stored payment wallet is used as
    ///      the fund wallet, so bids never carry wallets. Milestones may not
    ///      pre-declare themselves as released.
    function createProposal(
        uint256 _companyId,
        bytes32 _specContentHash,
        bytes32 _ipfsHash,
        uint256 _cost,
        bool _depositRequired,
        Milestone[] memory _milestones
    ) external {
        if (projectLifecycle != PROJECT_LIFECYCLE.PROPOSAL) revert InvalidProjectLifecycle();
        if (block.timestamp > proposalDeadline) revert ProposalDeadlinePassed();
        if (_milestones.length <= 1 || _milestones.length > MAX_MILESTONES) revert InvalidMilestoneCount();
        if (_cost > budgetCap) revert BudgetTooHigh();
        if (_specContentHash == bytes32(0) || _ipfsHash == bytes32(0)) revert InvalidHash();
        if (companyHasProposal[_companyId]) revert AlreadySubmittedProposal();

        (address companyAdminWallet, address companyPaymentWallet,, bool companyActive) =
            companyRegistry.companies(_companyId);
        if (!companyActive) revert CompanyNotActive();
        if (companyAdminWallet != msg.sender) revert UnauthorisedCalled();

        uint256 totalCost;
        for (uint256 x; x < _milestones.length; x++) {
            Milestone memory localMilestone = _milestones[x];
            if (localMilestone.amount == 0) revert ZeroAmount();
            if (localMilestone.released) revert MilestoneReleased();
            totalCost += localMilestone.amount;
        }
        if (totalCost != _cost) revert MilestonesDontMatchCost();

        // Field-by-field storage assignment (with a per-element push for the
        // milestones array): a whole-struct copy containing a memory array is
        // unsupported by the legacy (non-viaIR) pipeline, which forge
        // coverage uses unless --ir-minimum is passed.
        Proposal storage proposal = proposals[numberOfProposals];
        proposal.id = numberOfProposals;
        proposal.cost = _cost;
        proposal.admin = companyAdminWallet;
        proposal.fundWallet = companyPaymentWallet;
        proposal.specContentHash = _specContentHash;
        proposal.ipfsHash = _ipfsHash;
        proposal.depositRequired = _depositRequired;
        for (uint256 x; x < _milestones.length; x++) {
            proposal.milestones.push(_milestones[x]);
        }

        emit ProposalCreated(numberOfProposals, _companyId, companyAdminWallet, _cost);

        companyHasProposal[_companyId] = true;
        numberOfProposals++;
    }

    /// @notice Casts one vote for one proposal.
    /// @param _proposalId The proposal being voted for.
    /// @dev Open during VOTING only, until the voting deadline (time-enforced,
    ///      not admin-discretion). One member, one vote, recorded on-chain for
    ///      transparency and mirrored off-chain for lookup.
    function voteForProposal(uint256 _proposalId) external proposalExists(_proposalId) {
        if (projectLifecycle != PROJECT_LIFECYCLE.VOTING) revert InvalidProjectLifecycle();
        if (block.timestamp >= votingDeadline) revert VotingClosed();
        if (hasVoted[msg.sender]) revert UserAlreadyVoted();
        numberOfVotesPerProposal[_proposalId]++;

        hasVoted[msg.sender] = true;

        emit VoteCast(msg.sender, _proposalId);
    }

    // --------------------------------------------------------------------------
    // ---------------------------------------> MILESTONE CHANGES <--------------
    // --------------------------------------------------------------------------

    // Milestone approvals and fund releases happen inside the ProjectEscrow:
    // the builder first declares the milestone complete with evidence
    // (submitMilestoneComplete), then admin/member signatures are submitted in
    // EIP-712 batches, and the escrow auto-releases once the derived 3-of-5
    // (or 2-of-2 fallback) rule is met. Governance only tracks the lifecycle.

    /// @dev Guards every function that addresses a stored proposal by id.
    modifier proposalExists(uint256 _proposalId) {
        if (_proposalId >= numberOfProposals) revert ProposalNonExistent();
        _;
    }
}
