// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPaymentToken} from "./Interfaces/IPaymentToken.sol";
import {IProjectConfig} from "./Interfaces/IProjectConfig.sol";
import {CompanyRegistry} from "./CompanyRegistry.sol";
import {ProjectGovernance} from "./ProjectGovernance.sol";
import {ProjectEscrow} from "./ProjectEscrow.sol";

/// @title ProjectFactory
/// @notice The single entry point for creating tenders. Holds the platform
///         roles (who may create projects), the global minimum duration
///         policy, the VRF v2.5 configuration shared by every project, and
///         the mint/burn authority over the payment token for project
///         escrows.
/// @dev Deploys one ProjectGovernance per project via `new` (not a clone -
///      governance inherits Chainlink's VRFConsumerBaseV2Plus which needs its
///      coordinator in the constructor). ProjectEscrow clones are deployed
///      later by each governance contract at award time.
contract ProjectFactory is AccessControl {
    bytes32 public constant CREATE_PROJECT_ROLE = keccak256("CREATE_PROJECT_ROLE");
    uint256 public constant MAX_COMMITTEE_FEE_PER_SIGNATURE = 1000; // Hard cap on per-signature committee fees (GES).

    // --------------------------------------------------------------------------
    // ----------------------------------------> STORAGE <-----------------------
    // --------------------------------------------------------------------------
    //
    // Slot 1 (16 of 32 bytes used): minimum duration policy.
    uint64 public minimumProposalSubmissionDuration; // 8 bytes.
    uint64 public minimumVotingDuration; // 8 bytes.

    // Wallets / contracts - 20 bytes each, one per slot.
    address public token; // The payment token minted into project escrows.
    CompanyRegistry public companyRegistry; // Companies allowed to bid on tenders.

    mapping(address => bool) public isProject; // Registered project governance contracts.

    uint256 public projectCount;
    uint256 public globalMinimumVotingDuration;
    IProjectConfig.VRFConfig public vrfConfig;

    address public immutable PROJECT_ESCROW_IMPLEMENTATION; // Cloned per awarded project.

    // --------------------------------------------------------------------------
    // -----------------------------------> ERRORS / EVENTS <---------------------
    // --------------------------------------------------------------------------

    error AddressZero();
    error ZeroBudget();
    error InvalidProposalSubmissionDuration();
    error InvalidVotingDuration();
    error InvalidDeliberationWindow();
    error InvalidCategory();
    error InvalidDepartment();
    error InvalidTitle();
    error InvalidHash();
    error ProjectNonExistent();
    error ZeroAmount();
    error InvalidVRFConfig();
    error FeeTooHigh();

    event ProjectCreated(address indexed projectInstance);
    event ProjectFunded(address indexed projectEscrow, uint256 amount);
    event GlobalMinimumVotingDurationUpdated(uint256 newGlobalMinimum);

    /// @notice Deploys the platform core.
    /// @param _globalMinimumVotingDuration Global floor for the voting window.
    /// @param _minimumProposalSubmissionDuration Minimum proposal window.
    /// @param _minimumVotingDuration Minimum voting window (per project).
    /// @param _paymentToken The payment token funded into project escrows.
    /// @param _escrowImplementation The ProjectEscrow implementation that
    ///        every awarded project clones.
    /// @param _createProjectSafeWallet Wallet holding CREATE_PROJECT_ROLE -
    ///        the only actor allowed to create projects.
    /// @param _companyRegistry Registry of companies allowed to bid.
    /// @param _vrfConfig Shared Chainlink VRF v2.5 subscription/lane config.
    /// @dev The deployer receives DEFAULT_ADMIN_ROLE. All zero-value VRF
    ///      fields are rejected up front so no project can be created against
    ///      a broken configuration.
    constructor(
        uint256 _globalMinimumVotingDuration,
        uint64 _minimumProposalSubmissionDuration,
        uint64 _minimumVotingDuration,
        address _paymentToken,
        address _escrowImplementation,
        address _createProjectSafeWallet,
        address _companyRegistry,
        IProjectConfig.VRFConfig memory _vrfConfig
    ) {
        if (
            _paymentToken == address(0) || _escrowImplementation == address(0) || _createProjectSafeWallet == address(0)
                || _companyRegistry == address(0)
        ) revert AddressZero();

        if (
            _vrfConfig.coordinator == address(0) || _vrfConfig.subscriptionId == 0 || _vrfConfig.keyHash == bytes32(0)
                || _vrfConfig.callbackGasLimit == 0
        ) revert InvalidVRFConfig();

        _updateGlobalMinimumVotingDuration(_globalMinimumVotingDuration);

        _grantRole(CREATE_PROJECT_ROLE, _createProjectSafeWallet);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        token = _paymentToken;
        PROJECT_ESCROW_IMPLEMENTATION = _escrowImplementation;
        companyRegistry = CompanyRegistry(_companyRegistry);
        minimumProposalSubmissionDuration = _minimumProposalSubmissionDuration;
        minimumVotingDuration = _minimumVotingDuration;
        vrfConfig = _vrfConfig;
    }

    // --------------------------------------------------------------------------
    // -----------------------------------------> PROJECT LIFECYCLE <-------------
    // --------------------------------------------------------------------------

    /// @notice Creates a new project (tender) with its own governance contract.
    /// @param _config The tender configuration.
    /// @return projectGovernanceInstanceAddr The deployed governance contract.
    /// @dev CREATE_PROJECT_ROLE only. Every field is validated here so a
    ///      malformed tender can never exist on-chain: deadlines must respect
    ///      the platform minimums, the budget must be non-zero, and the
    ///      content identifiers must be present. The deployed governance
    ///      contract is registered in isProject, which later lets it mint the
    ///      escrow funding.
    function createProject(IProjectConfig.ProjectConfig memory _config)
        external
        onlyRole(CREATE_PROJECT_ROLE)
        returns (address projectGovernanceInstanceAddr)
    {
        if (_config.governanceSafeWallet == address(0)) revert AddressZero();
        if (_config.treasuryWallet == address(0)) revert AddressZero();
        if (_config.budgetCap == 0) revert ZeroBudget();
        if (_config.proposalDeadline < block.timestamp + minimumProposalSubmissionDuration) {
            revert InvalidProposalSubmissionDuration();
        }
        if (_config.votingDeadline < _config.proposalDeadline + minimumVotingDuration) revert InvalidVotingDuration();
        if (_config.deliberationWindow == 0) revert InvalidDeliberationWindow();
        if (_config.committeeFeePerSignature > MAX_COMMITTEE_FEE_PER_SIGNATURE) revert FeeTooHigh();
        if (_config.title == bytes32(0)) revert InvalidTitle();
        if (_config.category == bytes32(0)) revert InvalidCategory();
        if (_config.department == bytes32(0)) revert InvalidDepartment();
        if (_config.specContentHash == bytes32(0) || _config.ipfsHash == bytes32(0)) revert InvalidHash();

        projectCount++;

        projectGovernanceInstanceAddr = address(
            new ProjectGovernance(_config, vrfConfig, PROJECT_ESCROW_IMPLEMENTATION, token, address(companyRegistry))
        );

        isProject[projectGovernanceInstanceAddr] = true;

        emit ProjectCreated(projectGovernanceInstanceAddr);
    }

    /// @notice Mints the awarded budget plus the committee fee reserve into a
    ///         project's escrow.
    /// @param _projectEscrow The escrow receiving the funding.
    /// @param _amount The awarded cost plus the escrow's fee reserve; must not
    ///        exceed the project's budget cap plus that reserve.
    /// @dev Only registered project governance contracts may call this, and
    ///      only for their own escrow and within their own budget - a
    ///      governance can never mint supply to an arbitrary address or
    ///      beyond what its own tender permits. The fee reserve is the
    ///      escrow's own value (computed from its milestone count and fee),
    ///      so the escrow remains the source of truth for its funding.
    function mintInitialSupplyForProject(address _projectEscrow, uint256 _amount) external {
        ProjectGovernance gov = ProjectGovernance(msg.sender);
        if (!isProject[msg.sender]) revert ProjectNonExistent();
        if (address(gov.projectEscrow()) != _projectEscrow) revert ProjectNonExistent();
        if (_amount > gov.budgetCap() + ProjectEscrow(_projectEscrow).feeReserve()) revert ZeroAmount();

        IPaymentToken(token).mint(_projectEscrow, _amount);

        emit ProjectFunded(_projectEscrow, _amount);
    }

    // --------------------------------------------------------------------------
    // -------------------------------------------> POLICY <---------------------
    // --------------------------------------------------------------------------

    /// @notice Raises/lowers the global minimum voting duration floor.
    /// @dev DEFAULT_ADMIN_ROLE only; cannot be set to zero.
    function updateGlobalMinimumVotingDuration(uint256 _newGlobalMinimum) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateGlobalMinimumVotingDuration(_newGlobalMinimum);
    }

    /// @dev Shared setter used by the constructor and the admin update.
    function _updateGlobalMinimumVotingDuration(uint256 _newGlobalMinimum) internal {
        if (_newGlobalMinimum == 0) revert ZeroAmount();
        globalMinimumVotingDuration = _newGlobalMinimum;

        emit GlobalMinimumVotingDurationUpdated(_newGlobalMinimum);
    }
}
