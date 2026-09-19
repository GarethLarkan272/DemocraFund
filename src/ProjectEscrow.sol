// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPaymentToken} from "./Interfaces/IPaymentToken.sol";

/// @title ProjectEscrow
/// @notice Milestone-gated multisig escrow. The escrow contract itself is the
///         multisig: 1 admin + up to 3 community members + 1 builder. Approval
///         rules derive from how many members the committee draw actually
///         produced (M):
///
///           M | Signers | Milestone release        | Cancellation
///          ---|---------|--------------------------|---------------
///           3 |   5     | 3-of-5, admin+builder+1  | 4-of-5
///           2 |   4     | 3-of-4, admin+builder+1  | 3-of-4
///           1 |   3     | 3-of-3 (everyone)        | 2-of-3
///           0 |   2     | 2-of-2 (admin+builder)   | 2-of-2
///
///         The 3 community members can never release without the admin AND the
///         builder, and cancellation needs one more signature than a release so
///         it can never be triggered by the same bare majority.
///
///         Signatures are EIP-712 typed messages submitted in batches by a
///         relayer (anyone). Each signer commits to the specific milestone
///         evidence, and per-purpose nonces prevent replay. Verification goes
///         through SignatureChecker so both EOAs and ERC-1271 smart wallets are
///         supported (the account-abstraction future).
///
///         Committee fees are pull-based: the escrow is funded at award with
///         the budget PLUS a fee reserve (milestones x 3 members x fee), each
///         released milestone accrues a fee credit to every signing member,
///         and members collect what they are owed via collectFees(). There
///         are no external calls in the release path, so a member's wallet
///         can never brick the payout. Every fund movement (release,
///         settlement, fee collection, cancellation refund) preserves the
///         identity balance + released + settled + collected + returned ==
///         budget + feeReserve, so the escrow never drops below the fees it
///         still owes; cancellation refunds the treasury only what is NOT
///         owed to members, keeping uncollected fees payable afterwards.
///
///         Nonces are scoped per (signer, milestone) and per (signer,
///         cancellation), NOT a single per-signer counter: a relayer can
///         pre-collect signatures for several milestones (and a cancellation)
///         at once, because approving milestone 0 never invalidates the
///         pre-signed digest for milestone 1. Each purpose starts at 0 and
///         increments on use, so a used signature can never be replayed.
/// @dev Deployed as a minimal-proxy clone by ProjectGovernance at award time.
///      The EIP-712 domain separator is recomputed per clone address by OZ's
///      EIP712 (recompute path when address(this) != cachedThis) - no manual
///      caching.
contract ProjectEscrow is Initializable, ReentrancyGuard, EIP712 {
    using SafeERC20 for IPaymentToken;

    struct Milestone {
        uint256 amount;
        bytes32 evidenceHash;
        bool released;
    }

    struct Signature {
        address signer;
        bytes signature;
    }

    uint256 public constant MAX_MEMBERS = 3;
    uint256 public constant MAX_MILESTONES = 24;
    uint8 public constant ADMIN_SLOT = 0;

    bytes32 public constant MILESTONE_APPROVAL_TYPEHASH =
        keccak256("MilestoneApproval(uint256 milestoneIndex,bytes32 evidenceHash,uint256 nonce)");
    bytes32 public constant CANCELLATION_APPROVAL_TYPEHASH =
        keccak256("CancellationApproval(bytes32 reasonHash,uint256 nonce)");
    bytes32 public constant ALTERNATE_PROMOTION_TYPEHASH =
        keccak256("AlternatePromotion(uint256 alternateIndex,uint256 memberIndex,uint256 nonce)");

    // --------------------------------------------------------------------------
    // ----------------------------------------> STORAGE <-----------------------
    // --------------------------------------------------------------------------
    //
    // Slot 1 (22 of 32 bytes used): token + lifecycle flags.
    IPaymentToken public token;
    bool public cancelled;
    bool public committeeFinalized;

    // Wallets - 20 bytes each, one per slot.
    address public projectWallet; // Builder's fund wallet; receives every release.
    address public treasuryWallet; // Receives the remaining balance on cancellation/abort.
    address public projectGovernanceContract; // The controlling governance clone; set at initialize.
    address public adminSigner; // Signer slot 0 - the government representative.
    address public builderSigner; // Signer slot M+1 - the winning builder.

    // Budget accounting - 32 bytes each, one per slot.
    uint256 public totalProjectBudget;
    uint256 public totalReleased;
    uint256 public totalReturnedOnCancellation;
    uint256 public settlementPaid;
    uint256 public currentMilestoneIndex;
    uint256 public cancellationApprovalCount;
    uint256 public committeeFeePerSignature; // Accrued per member per milestone they sign.

    // Committee fee liabilities - 32 bytes each, one per slot.
    uint256 public feeReserve; // Extra tokens funded at award (milestones x 3 members x fee).
    uint256 public totalUncollectedFees; // Sum of every member's uncollected feeCredits.
    uint256 public feesCollected; // Total fees pulled by members so far.

    // Committee fee lifecycle - 32 bytes each, one per slot.
    uint256 public totalSweptToTreasury; // Un-owed reserve surplus returned to the treasury on completion.

    // Commitments - 32 bytes.
    bytes32 public cancellationReasonHash;

    // Committee signers, set once by setCommitteeMembers.
    address[] public memberSigners;
    address[] public alternates;

    // The milestone schedule; the escrow is the source of truth for releases.
    Milestone[] public milestones;

    // Committee fee credits: what each member is owed but has not collected.
    // Accrued on milestone release (pull-based, no external calls in the
    // release path), collected by the member themselves via collectFees().
    mapping(address => uint256) public feeCredits;

    // Signature bitmaps, one bit per signer slot.
    // Slots: 0 = admin, 1..M = members, M+1 = builder (M = memberSigners.length).
    mapping(uint256 => uint256) private _milestoneSigBitmap;
    uint256 private _cancellationSigBitmap;
    uint256 private _promotionSigBitmap;

    // Per-purpose signature nonces (see contract docs): milestone nonces are
    // keyed by milestone so pre-signed batches for different milestones never
    // collide; cancellation and promotion each have their own sequence.
    mapping(address signer => mapping(uint256 milestone => uint256 nonce)) public milestoneNonces;
    mapping(address signer => uint256 nonce) public cancellationNonces;
    mapping(address signer => uint256 nonce) public promotionNonces;

    // --------------------------------------------------------------------------
    // -----------------------------------> ERRORS / EVENTS <---------------------
    // --------------------------------------------------------------------------

    error MilestoneAlreadyReleased();
    error AccountingMismatch();
    error AddressZero();
    error ZeroBudget();
    error ZeroAmount();
    error ProjectCancelled();
    error SettlementTooHigh();
    error UnauthorisedCalled();
    error NotSigner();
    error NotBuilder();
    error BuilderMustSubmitFirst();
    error BuilderMustSubmitDirectly();
    error AlreadySigned();
    error InvalidHash();
    error NoMilestones();
    error InvalidMilestoneCount();
    error MilestonesDontMatchBudget();
    error AllMilestonesReleased();
    error DuplicateSigner();
    error InvalidSignature();
    error CommitteeNotFinalized();
    error CommitteeAlreadyFinalized();
    error TooManyMembers();
    error TooManyAlternates();
    error ReasonMismatch();
    error NoAlternates();
    error InvalidMemberIndex();
    error InvalidAlternateIndex();
    error ProjectStillActive();

    event MilestoneApproved(uint256 indexed milestoneIndex, address indexed signer);
    event MilestoneCompletionSubmitted(uint256 indexed milestoneIndex, bytes32 evidenceHash);
    event MilestoneReleased(uint256 indexed milestoneIndex, address indexed projectWallet, uint256 amount);
    event CommitteeFeeAccrued(uint256 indexed milestoneIndex, address indexed member, uint256 amount);
    event FeesCollected(address indexed member, uint256 amount);
    event SurplusSwept(address indexed treasuryWallet, uint256 amount);
    event CancellationApproved(address indexed signer, bytes32 reasonHash);
    event ProjectTerminated(address indexed treasuryWallet, uint256 returnedAmount);
    event CommitteeFinalized(address[] members, address[] alternates);
    event SettlementPaid(uint256 amount);
    event AlternatePromoted(uint256 indexed memberIndex, address indexed promotedMember);

    /// @notice Disables initializers on the implementation so that only clones
    ///         can be initialized. The EIP-712 name/version are constants for
    ///         every clone.
    constructor() EIP712("DemocraFund", "1") {
        _disableInitializers();
    }

    /// @notice One-time setup, called by the governance contract immediately
    ///         after the clone is deployed at award time.
    /// @param _projectWallet The winning proposal's fund wallet - the builder's
    ///        payment address and, at the same time, the builder signer.
    /// @param _treasuryWallet Where remaining funds go on cancellation or abort.
    /// @param _token The payment token held in escrow.
    /// @param _adminSigner The government representative (governance safe wallet).
    /// @param _builderSigner The builder signer; must differ from the admin.
    /// @param _totalProjectBudget The full awarded budget; the milestone amounts
    ///        must sum to exactly this.
    /// @param _milestoneAmounts The payment schedule, one amount per milestone.
    /// @param _committeeFeePerSignature Tokens minted to each committee member
    ///        per milestone they sign (0 disables committee compensation).
    /// @dev Assumes the caller (msg.sender) is the controlling governance
    ///      contract - it becomes projectGovernanceContract. The committee
    ///      members are NOT set here; they arrive later via
    ///      setCommitteeMembers once the VRF draw completes.
    function initialize(
        address _projectWallet,
        address _treasuryWallet,
        address _token,
        address _adminSigner,
        address _builderSigner,
        uint256 _totalProjectBudget,
        uint256[] calldata _milestoneAmounts,
        uint256 _committeeFeePerSignature
    ) external initializer {
        if (
            _projectWallet == address(0) || _treasuryWallet == address(0) || _token == address(0)
                || _adminSigner == address(0) || _builderSigner == address(0)
        ) revert AddressZero();

        if (_totalProjectBudget == 0) revert ZeroBudget();
        if (_milestoneAmounts.length == 0) revert NoMilestones();
        if (_milestoneAmounts.length > MAX_MILESTONES) revert InvalidMilestoneCount();
        if (_adminSigner == _builderSigner) revert DuplicateSigner();

        uint256 totalCost;
        for (uint256 i; i < _milestoneAmounts.length; i++) {
            if (_milestoneAmounts[i] == 0) revert ZeroAmount();
            totalCost += _milestoneAmounts[i];
        }
        if (totalCost != _totalProjectBudget) revert MilestonesDontMatchBudget();

        totalProjectBudget = _totalProjectBudget;
        committeeFeePerSignature = _committeeFeePerSignature;
        // Fund the maximum possible fee liability up front: every member of a
        // full 3-member committee signing every milestone. The actual draw
        // (VRF) may produce a smaller committee, in which case the un-owed
        // surplus returns to the treasury on cancellation. The reserve is
        // minted into the escrow on top of the budget at award time.
        feeReserve = _milestoneAmounts.length * MAX_MEMBERS * _committeeFeePerSignature;
        token = IPaymentToken(_token);
        projectWallet = _projectWallet;
        treasuryWallet = _treasuryWallet;
        adminSigner = _adminSigner;
        builderSigner = _builderSigner;
        projectGovernanceContract = msg.sender;

        for (uint256 i; i < _milestoneAmounts.length; i++) {
            milestones.push(Milestone({amount: _milestoneAmounts[i], evidenceHash: bytes32(0), released: false}));
        }
    }

    // --------------------------------------------------------------------------
    // ----------------------------------------> COMMITTEE SETUP <----------------
    // --------------------------------------------------------------------------

    /// @notice Sets the community committee drawn via VRF and finalises the
    ///         escrow. Called by the governance contract either immediately at
    ///         award (pool too small to draw) or from the VRF fulfillment
    ///         callback.
    /// @param _members The community members, up to MAX_MEMBERS. An empty array
    ///        means no community committee (M = 0, 2-of-2 fallback).
    /// @param _alternates Backup signers to promote if a member stalls.
    /// @dev Can only be called once; until it is called, no approvals and no
    ///      cancellation are possible (committeeIsFinalized gates them), so
    ///      the 2-of-2 fallback rule can never apply while the draw is pending.
    function setCommitteeMembers(address[] memory _members, address[] memory _alternates)
        external
        onlyGovernanceContract
    {
        if (committeeFinalized) revert CommitteeAlreadyFinalized();
        if (cancelled) revert ProjectCancelled();
        if (_members.length > MAX_MEMBERS) revert TooManyMembers();
        if (_alternates.length > MAX_MEMBERS) revert TooManyAlternates();

        _validateMemberList(_members, _alternates);

        memberSigners = _members;
        alternates = _alternates;
        committeeFinalized = true;

        emit CommitteeFinalized(_members, _alternates);
    }

    // --------------------------------------------------------------------------
    // ----------------------------------------> MILESTONE APPROVAL <-------------
    // --------------------------------------------------------------------------

    /// @notice The builder declares the current milestone complete and submits
    ///         the supporting evidence (photos, invoices...).
    /// @param _evidenceHash IPFS hash (or similar) of the builder's evidence.
    /// @dev Counts as the builder's signature and locks in the evidence hash
    ///      that every other signer cryptographically commits to. It is
    ///      immutable from this point on. Only the builder can call this - it
    ///      is the "I am done" claim that every approval refers to.
    function submitMilestoneComplete(bytes32 _evidenceHash) external nonReentrant projectOpen committeeIsFinalized {
        if (msg.sender != builderSigner) revert NotBuilder();

        uint256 index = currentMilestoneIndex;
        _checkMilestoneOpen(index);
        if (_evidenceHash == bytes32(0)) revert InvalidHash();

        uint8 slot = _signerSlot(msg.sender);
        if (_hasSigned(_milestoneSigBitmap[index], slot)) revert AlreadySigned();

        Milestone storage milestone = milestones[index];
        milestone.evidenceHash = _evidenceHash;

        _milestoneSigBitmap[index] = _setSigned(_milestoneSigBitmap[index], slot);
        emit MilestoneCompletionSubmitted(index, _evidenceHash);

        _tryReleaseMilestone(index);
    }

    /// @notice Submits a batch of EIP-712 approval signatures for the current
    ///         milestone.
    /// @param _signatures Signer + signature pairs, recoverable via
    ///        SignatureChecker. Each signature commits to the exact
    ///        (milestoneIndex, evidenceHash, signer nonce).
    /// @dev Can only run after the builder has submitted their evidence
    ///      (BuilderMustSubmitFirst). Signatures are persisted across batches,
    ///      so different signers can approve in different transactions; the
    ///      release fires automatically once the derived rule is met. The
    ///      builder cannot sign here - they must use submitMilestoneComplete.
    function approveMilestone(Signature[] calldata _signatures)
        external
        nonReentrant
        projectOpen
        committeeIsFinalized
    {
        uint256 index = currentMilestoneIndex;
        _checkMilestoneOpen(index);

        Milestone storage milestone = milestones[index];
        if (milestone.evidenceHash == bytes32(0)) revert BuilderMustSubmitFirst();

        for (uint256 i; i < _signatures.length; i++) {
            address signer = _signatures[i].signer;
            uint8 slot = _signerSlot(signer);
            if (slot == _builderSlot()) revert BuilderMustSubmitDirectly();

            if (_hasSigned(_milestoneSigBitmap[index], slot)) revert AlreadySigned();

            bytes32 digest = _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        MILESTONE_APPROVAL_TYPEHASH, index, milestone.evidenceHash, milestoneNonces[signer][index]
                    )
                )
            );
            if (!SignatureChecker.isValidSignatureNow(signer, digest, _signatures[i].signature)) {
                revert InvalidSignature();
            }

            milestoneNonces[signer][index]++;
            _milestoneSigBitmap[index] = _setSigned(_milestoneSigBitmap[index], slot);
            emit MilestoneApproved(index, signer);
        }

        _tryReleaseMilestone(index);
    }

    /// @dev Evaluates the derived release rule for a milestone and releases it
    ///      if met:
    ///        M = 0: admin AND builder (2-of-2).
    ///        M >= 1: >= 3 signatures total, admin AND builder, and >= 1 member
    ///      - the members can never band together alone.
    ///      On release, a committee fee is accrued to every member who signed
    ///      this milestone (never to admin, builder, or alternates). State is
    ///      updated before any external call (checks-effects-interactions) and
    ///      the accounting invariant is re-checked after.
    function _tryReleaseMilestone(uint256 _index) internal {
        Milestone storage milestone = milestones[_index];

        uint256 bitmap = _milestoneSigBitmap[_index];
        uint256 builderSlot = _builderSlot();
        uint256 memberMask = _memberMask();

        bool adminSigned = (bitmap & (1 << ADMIN_SLOT)) != 0;
        bool builderSigned = (bitmap & (1 << builderSlot)) != 0;

        bool releaseRuleMet = adminSigned && builderSigned
            && (memberSigners.length == 0 || (_popcount(bitmap) >= 3 && _popcount(bitmap & memberMask) >= 1));

        if (!releaseRuleMet) return;

        milestone.released = true;
        currentMilestoneIndex++;

        _releaseToProjectWallet(milestone.amount, _index);
        _accrueCommitteeFees(_index, bitmap);
    }

    /// @dev Accrues the committee fee to each member who signed the released
    ///      milestone. Pure storage - no external calls - so a member's fee
    ///      can never brick the release. The fee money is already in the
    ///      escrow (funded at award as the feeReserve); members pull what
    ///      they are owed via collectFees() - at any time, there is no
    ///      collection deadline. Cancelled projects pay nothing: a milestone
    ///      that never releases never accrues.
    function _accrueCommitteeFees(uint256 _index, uint256 _bitmap) internal {
        if (committeeFeePerSignature == 0 || memberSigners.length == 0) return;

        for (uint256 i; i < memberSigners.length; i++) {
            if (_hasSigned(_bitmap, uint8(i + 1))) {
                // Members occupy slots 1..M.
                address member = memberSigners[i];
                feeCredits[member] += committeeFeePerSignature;
                totalUncollectedFees += committeeFeePerSignature;
                emit CommitteeFeeAccrued(_index, member, committeeFeePerSignature);
            }
        }
        // Defense in depth: accruals are bounded by the funded reserve, so
        // the escrow can never owe more fees than it holds.
        if (totalUncollectedFees > feeReserve) revert AccountingMismatch();
    }

    /// @notice Collects the caller's accrued committee fees.
    /// @dev Pull-based: a member collects exactly what they are owed, and the
    ///      escrow only ever transfers out credited amounts. Works after a
    ///      cancellation too - cancellation refunds the treasury the balance
    ///      MINUS outstanding fee credits, so uncollected fees stay payable
    ///      indefinitely.
    function collectFees() external nonReentrant {
        uint256 owed = feeCredits[msg.sender];
        if (owed == 0) revert ZeroAmount();

        feeCredits[msg.sender] = 0;
        totalUncollectedFees -= owed;
        feesCollected += owed;

        token.safeTransfer(msg.sender, owed);
        emit FeesCollected(msg.sender, owed);
    }

    /// @notice Returns the un-owed fee reserve to the treasury once every
    ///         milestone has been released (the fee liability is final).
    /// @dev Called by the governance contract inside completeProject. The
    ///      surplus is whatever the escrow holds BEYOND the outstanding
    ///      credits - computing it from the live balance (rather than the
    ///      reserve minus accruals) makes the sweep idempotent: a second
    ///      call can never take the balance below what members are owed.
    function sweepSurplusToTreasury() external onlyGovernanceContract nonReentrant {
        if (cancelled) revert ProjectCancelled();
        if (currentMilestoneIndex < milestones.length) revert ProjectStillActive();

        uint256 surplus = token.balanceOf(address(this)) - totalUncollectedFees;
        if (surplus == 0) return;

        totalSweptToTreasury += surplus;
        token.safeTransfer(treasuryWallet, surplus);
        emit SurplusSwept(treasuryWallet, surplus);
    }

    /// @notice Auto-releases the deposit, which is always the first milestone,
    ///         without committee signatures.
    /// @dev Called by the governance contract at award time when the winning
    ///      proposal requested a deposit. Does not require committeeFinalized
    ///      by design - the deposit is part of the award, not of the approval
    ///      loop. Its evidence hash is recorded as bytes32("Deposit").
    function releaseDeposit() external onlyGovernanceContract nonReentrant projectOpen {
        uint256 index = currentMilestoneIndex;
        if (index >= milestones.length) revert AllMilestonesReleased();
        if (milestones[index].released) revert MilestoneAlreadyReleased();

        Milestone storage milestone = milestones[index];
        milestone.released = true;
        milestone.evidenceHash = bytes32("Deposit");
        currentMilestoneIndex++;

        _releaseToProjectWallet(milestone.amount, index);
    }

    // --------------------------------------------------------------------------
    // -----------------------------------> CANCELLATION / SETTLEMENT <-----------
    // --------------------------------------------------------------------------

    /// @notice Terminates the project via the cancellation threshold.
    /// @param _reasonHash The shared, mandatory public justification. All
    ///        signatures commit to the same hash, which is locked after the
    ///        first signature (ReasonMismatch if a later batch disagrees).
    /// @param _signatures EIP-712 cancellation approvals.
    /// @dev Once the derived threshold is met (M+1 of M+2, or 2-of-2 with no
    ///      members) the escrow is cancelled and the entire remaining balance
    ///      is redirected to the treasury wallet. From that point on no
    ///      milestone activity is possible (projectOpen blocks everything).
    function approveCancellation(bytes32 _reasonHash, Signature[] calldata _signatures)
        external
        nonReentrant
        projectOpen
        committeeIsFinalized
    {
        if (_reasonHash == bytes32(0)) revert InvalidHash();
        if (cancellationApprovalCount > 0 && _reasonHash != cancellationReasonHash) revert ReasonMismatch();
        if (cancellationApprovalCount == 0) cancellationReasonHash = _reasonHash;

        for (uint256 i; i < _signatures.length; i++) {
            address signer = _signatures[i].signer;
            uint8 slot = _signerSlot(signer);

            if (_hasSigned(_cancellationSigBitmap, slot)) revert AlreadySigned();

            bytes32 digest = _hashTypedDataV4(
                keccak256(abi.encode(CANCELLATION_APPROVAL_TYPEHASH, _reasonHash, cancellationNonces[signer]))
            );
            if (!SignatureChecker.isValidSignatureNow(signer, digest, _signatures[i].signature)) {
                revert InvalidSignature();
            }

            cancellationNonces[signer]++;
            _cancellationSigBitmap = _setSigned(_cancellationSigBitmap, slot);
            cancellationApprovalCount++;
            emit CancellationApproved(signer, _reasonHash);
        }

        if (_popcount(_cancellationSigBitmap) >= _cancellationThreshold()) {
            cancelled = true;

            _refundTreasury();
        }
    }

    /// @dev Refunds the treasury everything the escrow holds EXCEPT the
    ///      outstanding fee credits - uncollected fees stay payable to their
    ///      members indefinitely after termination. With no fees owed this
    ///      is the full remaining balance.
    function _refundTreasury() internal {
        uint256 remainingBalance = token.balanceOf(address(this));
        uint256 owedFees = totalUncollectedFees;
        uint256 treasuryRefund = remainingBalance > owedFees ? remainingBalance - owedFees : 0;

        if (treasuryRefund > 0) {
            totalReturnedOnCancellation = treasuryRefund;
            token.safeTransfer(treasuryWallet, treasuryRefund);
        }

        emit ProjectTerminated(treasuryWallet, treasuryRefund);
    }

    /// @notice Aborts the project before the committee is finalised.
    /// @dev Only callable by the governance contract while the VRF draw is
    ///      still pending (committeeFinalized == false). There is no committee
    ///      yet, so the admin alone is the authority; every token returns to
    ///      the treasury. This closes the award-to-fulfillment window where a
    ///      2-of-2 cancellation would otherwise be possible.
    function abort() external onlyGovernanceContract nonReentrant projectOpen {
        if (committeeFinalized) revert CommitteeAlreadyFinalized();

        cancelled = true;

        // No fee can have accrued before finalization (the deposit is the
        // only pre-finalization release and it accrues nothing), so the
        // refund is the full balance - but route it through the shared
        // liability-aware refund anyway.
        _refundTreasury();
    }

    /// @notice Replaces a stalled committee member with an alternate.
    /// @param _alternateIndex Index into alternates (the alternate stepping up).
    /// @param _memberIndex Index into memberSigners (the member being replaced).
    /// @param _signatures EIP-712 promotion approvals. The rule mirrors the
    ///        milestone release rule: admin AND builder, plus at least one
    ///        member when the committee has more than one.
    /// @dev The promoted alternate takes the replaced member's slot: its bits
    ///      are cleared in the current milestone and cancellation bitmaps so
    ///      the new member can sign fresh (a pre-promotion signature by the
    ///      stale member is voided with the slot). The promoted alternate is
    ///      removed from the alternates list. Thresholds re-derive from
    ///      memberSigners.length, so M does not change.
    function promoteAlternate(uint256 _alternateIndex, uint256 _memberIndex, Signature[] calldata _signatures)
        external
        nonReentrant
        projectOpen
        committeeIsFinalized
    {
        if (alternates.length == 0) revert NoAlternates();
        if (_alternateIndex >= alternates.length) revert InvalidAlternateIndex();
        if (_memberIndex >= memberSigners.length) revert InvalidMemberIndex();

        for (uint256 i; i < _signatures.length; i++) {
            address signer = _signatures[i].signer;
            uint8 slot = _signerSlot(signer);

            if (_hasSigned(_promotionSigBitmap, slot)) revert AlreadySigned();

            bytes32 digest = _hashTypedDataV4(
                keccak256(
                    abi.encode(ALTERNATE_PROMOTION_TYPEHASH, _alternateIndex, _memberIndex, promotionNonces[signer])
                )
            );
            if (!SignatureChecker.isValidSignatureNow(signer, digest, _signatures[i].signature)) {
                revert InvalidSignature();
            }

            promotionNonces[signer]++;
            _promotionSigBitmap = _setSigned(_promotionSigBitmap, slot);
        }

        if (!_promotionThresholdMet(_promotionSigBitmap)) revert InvalidSignature();

        address promoted = alternates[_alternateIndex];
        memberSigners[_memberIndex] = promoted;

        // Remove the alternate from the list (swap + pop).
        alternates[_alternateIndex] = alternates[alternates.length - 1];
        alternates.pop();

        // The replaced member's slot now belongs to the promoted alternate:
        // clear their stale signature bits so the newcomer signs fresh.
        uint8 replacedSlot = uint8(_memberIndex + 1);
        _milestoneSigBitmap[currentMilestoneIndex] &= ~(uint256(1) << replacedSlot);
        _cancellationSigBitmap &= ~(uint256(1) << replacedSlot);
        _promotionSigBitmap = 0;

        emit AlternatePromoted(_memberIndex, promoted);
    }

    /// @notice Pays a partial settlement to the builder out of the remaining
    ///         escrow balance.
    /// @param _settlementAmount Amount to pay, capped by what is left after
    ///        releases and any previous settlements.
    /// @dev Intended for negotiated compensation before a cancellation is
    ///      finalised (e.g. for work already done). Governed by the
    ///      governance contract (admin-only there).
    function releaseSettlement(uint256 _settlementAmount) external onlyGovernanceContract projectOpen {
        if (_settlementAmount > totalProjectBudget - totalReleased - settlementPaid) revert SettlementTooHigh();
        token.safeTransfer(projectWallet, _settlementAmount);
        settlementPaid += _settlementAmount;

        emit SettlementPaid(_settlementAmount);
    }

    // --------------------------------------------------------------------------
    // ------------------------------------------> VIEWS <-----------------------
    // --------------------------------------------------------------------------

    /// @notice Whether an address is one of the 5 (or fewer) committee signers.
    function isSigner(address _account) public view returns (bool) {
        if (_account == adminSigner || _account == builderSigner) return true;
        for (uint256 i; i < memberSigners.length; i++) {
            if (_account == memberSigners[i]) return true;
        }
        return false;
    }

    /// @notice Whether a specific signer has signed a specific milestone.
    /// @return False for non-signers (rather than reverting).
    function hasSigned(uint256 _milestoneIndex, address _signer) external view returns (bool) {
        if (!isSigner(_signer)) return false;
        return _hasSigned(_milestoneSigBitmap[_milestoneIndex], _signerSlot(_signer));
    }

    /// @notice Whether a specific signer has signed the cancellation.
    /// @return False for non-signers (rather than reverting).
    function hasSignedCancellation(address _signer) external view returns (bool) {
        if (!isSigner(_signer)) return false;
        return _hasSigned(_cancellationSigBitmap, _signerSlot(_signer));
    }

    /// @notice Whether every milestone has been released (project completion).
    function allMilestonesReleased() external view returns (bool) {
        return currentMilestoneIndex >= milestones.length;
    }

    /// @notice The current committee members (storage array getter wrapper).
    function getMemberSigners() external view returns (address[] memory) {
        return memberSigners;
    }

    /// @notice The current alternates (storage array getter wrapper).
    function getAlternates() external view returns (address[] memory) {
        return alternates;
    }

    /// @notice EIP-712 digest a signer must sign to approve a milestone.
    /// @param _milestoneIndex The milestone being approved.
    /// @param _evidenceHash The exact evidence hash the builder submitted.
    /// @param _signer The signer's address (embeds their current nonce).
    /// @dev Relayers and the backend use this to produce signatures; it must
    ///      match the evidence hash stored on the milestone or verification
    ///      fails.
    function getMilestoneApprovalDigest(uint256 _milestoneIndex, bytes32 _evidenceHash, address _signer)
        external
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    MILESTONE_APPROVAL_TYPEHASH,
                    _milestoneIndex,
                    _evidenceHash,
                    milestoneNonces[_signer][_milestoneIndex]
                )
            )
        );
    }

    /// @notice EIP-712 digest a signer must sign to approve a cancellation.
    /// @param _reasonHash The shared public justification.
    /// @param _signer The signer's address (embeds their cancellation nonce).
    function getCancellationApprovalDigest(bytes32 _reasonHash, address _signer) external view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(CANCELLATION_APPROVAL_TYPEHASH, _reasonHash, cancellationNonces[_signer]))
        );
    }

    /// @notice EIP-712 digest a signer must sign to promote an alternate.
    /// @param _alternateIndex The alternate stepping up.
    /// @param _memberIndex The stale member being replaced.
    /// @param _signer The signer's address (embeds their promotion nonce).
    function getAlternatePromotionDigest(uint256 _alternateIndex, uint256 _memberIndex, address _signer)
        external
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(
            keccak256(abi.encode(ALTERNATE_PROMOTION_TYPEHASH, _alternateIndex, _memberIndex, promotionNonces[_signer]))
        );
    }

    /// @notice The EIP-712 domain separator for this clone.
    /// @dev Recomputed per clone address by OZ EIP712 (see contract docs).
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // --------------------------------------------------------------------------
    // ------------------------------------------> INTERNALS <-------------------
    // --------------------------------------------------------------------------

    /// @dev Maps a signer address to its bitmap slot: 0 = admin, 1..M =
    ///      members (in order), M+1 = builder. Reverts for non-signers.
    function _signerSlot(address _account) internal view returns (uint8) {
        if (_account == adminSigner) return ADMIN_SLOT;
        for (uint256 i; i < memberSigners.length; i++) {
            if (_account == memberSigners[i]) return uint8(i + 1);
        }
        if (_account == builderSigner) return _builderSlot();
        revert NotSigner();
    }

    /// @dev The builder's slot is always the last one: M + 1.
    function _builderSlot() internal view returns (uint8) {
        return uint8(memberSigners.length + 1);
    }

    /// @dev Bitmask covering all member slots (bits 1..M).
    function _memberMask() internal view returns (uint256 mask) {
        for (uint256 i = 1; i <= memberSigners.length; i++) {
            mask |= (1 << i);
        }
    }

    /// @dev Cancellation needs one more signature than a release: 4-of-5,
    ///      3-of-4, 2-of-3 - or 2-of-2 in the memberless fallback.
    function _cancellationThreshold() internal view returns (uint256) {
        return memberSigners.length == 0 ? 2 : memberSigners.length + 1;
    }

    /// @dev Promotion mirrors the release rule: admin AND builder, plus at
    ///      least one member when the committee has more than one member
    ///      (M = 1: admin + builder alone may swap the single member).
    function _promotionThresholdMet(uint256 _bitmap) internal view returns (bool) {
        bool adminSigned = (_bitmap & (1 << ADMIN_SLOT)) != 0;
        bool builderSigned = (_bitmap & (1 << _builderSlot())) != 0;
        if (!adminSigned || !builderSigned) return false;
        if (memberSigners.length <= 1) return true;
        return _popcount(_bitmap & _memberMask()) >= 1;
    }

    /// @dev Validates the committee drawn via VRF: no zero addresses, no
    ///      duplicates, no overlap with the admin or builder, and no member
    ///      duplicated as an alternate.
    function _validateMemberList(address[] memory _members, address[] memory _alternates) internal view {
        for (uint256 i; i < _members.length; i++) {
            address m = _members[i];
            if (m == address(0)) revert AddressZero();
            if (m == adminSigner || m == builderSigner) revert DuplicateSigner();
            for (uint256 j = i + 1; j < _members.length; j++) {
                if (m == _members[j]) revert DuplicateSigner();
            }
            for (uint256 j; j < _alternates.length; j++) {
                if (m == _alternates[j]) revert DuplicateSigner();
            }
        }
        for (uint256 i; i < _alternates.length; i++) {
            address a = _alternates[i];
            if (a == address(0)) revert AddressZero();
            if (a == adminSigner || a == builderSigner) revert DuplicateSigner();
            for (uint256 j = i + 1; j < _alternates.length; j++) {
                if (a == _alternates[j]) revert DuplicateSigner();
            }
        }
    }

    /// @dev Guards against signing a milestone that is already released or
    ///      beyond the schedule.
    function _checkMilestoneOpen(uint256 _index) internal view {
        if (_index >= milestones.length) revert AllMilestonesReleased();
        if (milestones[_index].released) revert MilestoneAlreadyReleased();
    }

    /// @dev Transfers a milestone amount to the builder's wallet, updates the
    ///      accounting, and re-verifies the master identity: escrow balance
    ///      plus everything paid out (milestones, settlements, collected
    ///      fees, treasury refunds and sweeps) equals the budget plus the
    ///      funded fee reserve. Because the reserve covers all accruals, the
    ///      balance can never drop below what members are still owed in fees.
    function _releaseToProjectWallet(uint256 _amount, uint256 _index) internal {
        token.safeTransfer(projectWallet, _amount);
        totalReleased += _amount;
        if (
            token.balanceOf(address(this)) + totalReleased + settlementPaid + feesCollected
                + totalReturnedOnCancellation + totalSweptToTreasury != totalProjectBudget + feeReserve
        ) revert AccountingMismatch();

        emit MilestoneReleased(_index, projectWallet, _amount);
    }

    /// @dev Sets bit `_slot` in `_bitmap`.
    function _setSigned(uint256 _bitmap, uint8 _slot) internal pure returns (uint256) {
        return _bitmap | (uint256(1) << _slot);
    }

    /// @dev Reads bit `_slot` from `_bitmap`.
    function _hasSigned(uint256 _bitmap, uint8 _slot) internal pure returns (bool) {
        return ((_bitmap >> _slot) & 1) == 1;
    }

    /// @dev Brian Kernighan popcount: counts set bits (max 5 in practice).
    function _popcount(uint256 _x) internal pure returns (uint256 count) {
        while (_x != 0) {
            _x &= _x - 1;
            count++;
        }
    }

    /// @dev Guards every fund movement: nothing works after cancellation.
    modifier projectOpen() {
        if (cancelled) revert ProjectCancelled();
        _;
    }

    /// @dev Approvals and cancellation only exist once the committee is set.
    modifier committeeIsFinalized() {
        if (!committeeFinalized) revert CommitteeNotFinalized();
        _;
    }

    /// @dev Only the governance contract that initialized this clone may
    ///      perform privileged operations (abort, deposit, settlement).
    modifier onlyGovernanceContract() {
        if (msg.sender != projectGovernanceContract) revert UnauthorisedCalled();
        _;
    }
}
