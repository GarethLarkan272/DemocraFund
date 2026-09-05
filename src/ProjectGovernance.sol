// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";


contract ProjectGovernance is Initializable, AccessControl {

    enum PROJECT_LIFECYCLE {
        CREATED,
        PROPOSAL,
        VOTING,
        AWARDED,
        CONSTRUCTION,
        COMPLETE,
        CANCELLED
    }

    PROJECT_LIFECYCLE public projectLifecycle;

    //No contract ID exists, the contract address is already a random hash created to be unique, this will be used as the projectID
    uint256 public budgetCap;
    uint64 public proposalDeadline;
    uint64 public votingDeadline;
    bytes32 public category;
    bytes32 public department;
    bytes32 public title;

    //The keccak hash is also kept for onchain verification of the data in future.
    bytes32 public specContentHash;
    bytes32 public ipfsHash;

    bytes32 public constant PROJECT_GOVERNANCE_ROLE = keccak256("PROJECT_GOVERNANCE_ROLE");

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _budgetCap,
        uint64 _proposalDeadline,
        uint64 _votingDeadline,
        address _projectGovernanceSafeWallet,
        bytes32 _title,
        bytes32 _category,
        bytes32 _department,
        bytes32 _specContentHash,
        bytes32 _ipfsHash
    ) external initializer {
        budgetCap = _budgetCap;
        proposalDeadline = _proposalDeadline;
        votingDeadline = _votingDeadline;
        title = _title;
        category = _category;
        department = _department;
        specContentHash = _specContentHash;
        ipfsHash = _ipfsHash;

        _grantRole(DEFAULT_ADMIN_ROLE, _projectGovernanceSafeWallet);
    }
}
