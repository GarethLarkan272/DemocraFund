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

    event ProjectCreated(address indexed projectInstance);

    PaymentToken public immutable token;

    mapping(address => bool) public isProject;

    uint256 public projectCount;
    uint64 public minimumProposalSubmissionDuration;
    uint64 public minimumVotingDuration;
    address public immutable escrowImplementation;
    address public immutable projectGovernanceImplementation;

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
        escrowImplementation = _escrowImplementation;
        projectGovernanceImplementation = _projectGovernanceImplementation;
        minimumProposalSubmissionDuration = _minimumProposalSubmissionDuration;
        minimumVotingDuration = _minimumVotingDuration;
    }

    function createProject(
        uint256 _budgetCap,
        uint64 _proposalDeadline,
        uint64 _votingDeadline,
        address _projectGovernanceSafeWallet,
        bytes32 _department
    ) external onlyRole(CREATE_PROJECT_ROLE) returns (address projectGovernanceInstanceAddr) {
        if (_projectGovernanceSafeWallet == address(0)) { revert AddressZero(); }
        if (_budgetCap == 0) { revert ZeroBudget(); }
        if (_proposalDeadline < block.timestamp + minimumProposalSubmissionDuration) { revert InvalidProposalSubmissionDuration(); }
        if (_votingDeadline < _proposalDeadline + minimumVotingDuration) { revert InvalidVotingDuration(); }

        projectCount++;

        projectGovernanceInstanceAddr = projectGovernanceImplementation.clone();
        ProjectGovernance(projectGovernanceInstanceAddr).initialize(
            _budgetCap, 
            _proposalDeadline,
            _votingDeadline,
            _projectGovernanceSafeWallet,
            _department
        );

        isProject[projectGovernanceInstanceAddr] = true;

        emit ProjectCreated(projectGovernanceInstanceAddr);

    }
}
