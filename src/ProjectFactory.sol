// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "./Interfaces/IPaymentToken.sol";
import "./ProjectGovernance.sol";


contract ProjectFactory is AccessControl {
    using Clones for address;

    bytes32 public constant CREATE_PROJECT_ROLE = keccak256("CREATE_PROJECT_ROLE");

    error AddressZero();
    error ZeroBudget();
    error InvalidProposalSubmissionDuration();
    error InvalidVotingDuration();
    error InvalidCategory();
    error InvalidDepartment();
    error InvalidTitle();
    error InvalidHash();
    error ProjectNonExistent();
    error ZeroAmount();

    event ProjectCreated(address indexed projectInstance);

    address public token;

    mapping(address => bool) public isProject;

    uint256 public projectCount;
    uint256 public globalMinimumVotingDuration;
    uint64 public minimumProposalSubmissionDuration;
    uint64 public minimumVotingDuration;
    address public immutable PROJECT_ESCROW_IMPLEMENTATION;
    address public immutable PROJECT_GOVERNANCE_IMPLEMENTATION;


    constructor(
        uint256 _globalMinimumVotingDuration,
        uint64 _minimumProposalSubmissionDuration,
        uint64 _minimumVotingDuration,
        address _paymentToken,
        address _escrowImplementation,
        address _projectGovernanceImplementation,
        address _createProjectSafeWallet
    ) {
        if (
            _paymentToken == address(0) || 
            _escrowImplementation == address(0) || 
            _projectGovernanceImplementation == address(0) ||
            _createProjectSafeWallet == address(0)
        ) revert AddressZero();

        _updateGlobalMinimumVotingDuration(_globalMinimumVotingDuration);

        _grantRole(CREATE_PROJECT_ROLE, _createProjectSafeWallet); // can grant/revoke other roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // can grant/revoke other roles

        token = _paymentToken;
        PROJECT_ESCROW_IMPLEMENTATION = _escrowImplementation;
        PROJECT_GOVERNANCE_IMPLEMENTATION = _projectGovernanceImplementation;
        minimumProposalSubmissionDuration = _minimumProposalSubmissionDuration;
        minimumVotingDuration = _minimumVotingDuration;
    }

    function createProject(
        uint256 _budgetCap,
        uint64 _proposalDeadline,
        uint64 _votingDeadline,
        address _projectGovernanceSafeWallet,
        bytes32 _title,
        bytes32 _category,
        bytes32 _department,
        bytes32 _specContentHash,
        bytes32 _ipfsHash,
        bool _urgent
    ) external onlyRole(CREATE_PROJECT_ROLE) returns (address projectGovernanceInstanceAddr) {
        if (_projectGovernanceSafeWallet == address(0)) revert AddressZero(); 
        if (_budgetCap == 0) revert ZeroBudget(); 
        if (_proposalDeadline < block.timestamp + minimumProposalSubmissionDuration) revert InvalidProposalSubmissionDuration(); 
        if (_votingDeadline < _proposalDeadline + minimumVotingDuration) revert InvalidVotingDuration(); 
        if (_title == bytes32(0)) revert InvalidTitle();
        if (_category == bytes32(0)) revert InvalidCategory();
        if (_department == bytes32(0)) revert InvalidDepartment();
        if (
            _specContentHash == bytes32(0) || 
            _ipfsHash == bytes32(0)
        ) revert InvalidHash();

        projectCount++;

        projectGovernanceInstanceAddr = PROJECT_GOVERNANCE_IMPLEMENTATION.clone();
        ProjectGovernance(projectGovernanceInstanceAddr).initialize(
            _budgetCap, 
            _proposalDeadline,
            _votingDeadline,
            PROJECT_ESCROW_IMPLEMENTATION,
            _projectGovernanceSafeWallet,
            token,
            _title,
            _category,
            _department,
            _specContentHash,
            _ipfsHash,
            _urgent
        );

        isProject[projectGovernanceInstanceAddr] = true;

        emit ProjectCreated(projectGovernanceInstanceAddr);
    }

    function mintInitialSupplyForProject(
        address _projectEscrow,
        uint256 _amount
    ) external {
        if (!isProject[msg.sender]) revert ProjectNonExistent();

        IPaymentToken(token).mint(_projectEscrow, _amount);
    }

    function burnProjectTokensFromCancellation(
        address _projectEscrow,
        uint256 _amount
    ) external {
        if (!isProject[msg.sender]) revert ProjectNonExistent();

        IPaymentToken(token).burn(_projectEscrow, _amount);
    }

    function updateGlobalMinimumVotingDuration(uint256 _newGlobalMinimum) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _updateGlobalMinimumVotingDuration(_newGlobalMinimum);
    }

    function _updateGlobalMinimumVotingDuration(uint256 _newGlobalMinimum) internal {
        if(_newGlobalMinimum == 0) revert ZeroAmount();
        globalMinimumVotingDuration = _newGlobalMinimum;
    }
}
