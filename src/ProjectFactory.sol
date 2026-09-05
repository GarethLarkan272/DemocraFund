// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "./PaymentToken.sol";
//import "./ProjectEscrow.sol";
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

    event ProjectCreated(address indexed projectInstance);

    PaymentToken public immutable token;

    mapping(address => bool) public isProject;

    uint256 public projectCount;
    uint64 public minimumProposalSubmissionDuration;
    uint64 public minimumVotingDuration;
    address public immutable ESCROW_IMPLEMENTATION;
    address public immutable PROJECT_GOVERNANCE_IMPLEMENTATION;

    constructor(
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
        ) { 
            revert AddressZero();
        }

        _grantRole(CREATE_PROJECT_ROLE, _createProjectSafeWallet); // can grant/revoke other roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // can grant/revoke other roles

        token = PaymentToken(_paymentToken);
        ESCROW_IMPLEMENTATION = _escrowImplementation;
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
        bytes32 _ipfsHash
    ) external onlyRole(CREATE_PROJECT_ROLE) returns (address projectGovernanceInstanceAddr) {
        if (_projectGovernanceSafeWallet == address(0)) { revert AddressZero(); }
        if (_budgetCap == 0) { revert ZeroBudget(); }
        if (_proposalDeadline < block.timestamp + minimumProposalSubmissionDuration) { revert InvalidProposalSubmissionDuration(); }
        if (_votingDeadline < _proposalDeadline + minimumVotingDuration) { revert InvalidVotingDuration(); }
        if (_title == bytes32(0)) revert InvalidTitle();
        if (_category == bytes32(0)) revert InvalidCategory();
        if (_department == bytes32(0)) revert InvalidDepartment();
        if (_specContentHash == bytes32(0)) revert InvalidHash();
        if (_ipfsHash == bytes32(0)) revert InvalidHash();

        projectCount++;

        projectGovernanceInstanceAddr = PROJECT_GOVERNANCE_IMPLEMENTATION.clone();
        ProjectGovernance(projectGovernanceInstanceAddr).initialize(
            _budgetCap, 
            _proposalDeadline,
            _votingDeadline,
            _projectGovernanceSafeWallet,
            _title,
            _category,
            _department,
            _specContentHash,
            _ipfsHash
        );

        isProject[projectGovernanceInstanceAddr] = true;

        emit ProjectCreated(projectGovernanceInstanceAddr);

    }
}
