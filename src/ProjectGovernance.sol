// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import "./ProjectEscrow.sol";
import "./ProjectFactory.sol";
import "./Interfaces/IPaymentToken.sol";

contract ProjectGovernance is Initializable, AccessControl {

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
        uint256 numberOfMilestonesReleased;
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

    mapping(uint256 proposalCount => Proposal proposalInformation) public proposals;
    mapping(uint256 proposakId => uint256 proposalVotes) public numberOfVotesPerProposal;
    mapping(address user => bool voted) public hasVoted;

    PROJECT_LIFECYCLE public projectLifecycle;
    PROJECT_LIFECYCLE public cancelledForm;
    uint256 public winningProposalId;
    address public token;

    bool public urgent;

    //No contract ID exists, the contract address is already a random hash created to be unique, this will be used as the projectID
    uint256 public budgetCap;
    uint256 public numberOfProposals;
    uint256 public numberOfShortlistedProjects;
    uint256 public numberOfTotalMilestones;
    uint256 public votingOpenedTimestamp;
    uint64 public proposalDeadline;
    uint64 public votingDeadline;
    bytes32 public category;
    bytes32 public department;
    bytes32 public title;

    // Safe wallet created on awarding of project with the official admin address, 
    // 3 community server wallets as well as winning proposals admin address provided in the proposal.
    address public projectEscrowImplementation;

    ProjectFactory public projectFactory;
    ProjectEscrow public projectEscrow;

    //The keccak hash is also kept for onchain verification of the data in future.
    bytes32 public specContentHash;
    bytes32 public ipfsHash;

    bytes32 public constant PROJECT_COMMITTEE = keccak256("PROJECT_COMMITTEE");

    uint256 public constant MAX_MILESTONES = 24;

    error InvalidProjectLifecycle();
    error UserAlreadyVoted();
    error VotingTooShort();
    error ProposalsDurationTooShort();
    error ZeroAmount();
    error NotRegisteredEscrow();
    error ProjectCancelled();
    error BudgetTooHigh();
    error AddressZero();
    error MilestonesDontMatchCost();
    error ProposalDeadlinePassed();
    error InvalidMilestoneCount();
    error InvalidHash();
    error ProposalNonExistent();
    error MilestoneReleased();
    error ZeroMilestones();
    error UnauthorisedCaller();
    error MilestoneAlreadyReleased();

    event VoteCast(address indexed voter, uint256 indexed proposalId);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _budgetCap,
        uint64 _proposalDeadline,
        uint64 _votingDeadline,
        address _projectEscrowImplementation,
        address _projectGovernanceSafeWallet,
        address _paymentToken,
        bytes32 _title,
        bytes32 _category,
        bytes32 _department,
        bytes32 _specContentHash,
        bytes32 _ipfsHash,
        bool _urgent
    ) external initializer {
        budgetCap = _budgetCap;
        proposalDeadline = _proposalDeadline;
        votingDeadline = _votingDeadline;
        projectEscrowImplementation = _projectEscrowImplementation;
        title = _title;
        category = _category;
        department = _department;
        specContentHash = _specContentHash;
        ipfsHash = _ipfsHash;

        token = _paymentToken;
        urgent = _urgent;

        projectFactory = ProjectFactory(msg.sender);

        //Set to CANCELLED to ensure it doesn't default to CREATED.
        cancelledForm = PROJECT_LIFECYCLE.CANCELLED;

        _grantRole(DEFAULT_ADMIN_ROLE, _projectGovernanceSafeWallet);
    }

    // ----------------------------------------------------------------------------------------------------------
    // --------------------------------------> LIFECYCLE CHANGE FUNCTIONS <--------------------------------------
    // ----------------------------------------------------------------------------------------------------------

    function acceptProposals() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(projectLifecycle != PROJECT_LIFECYCLE.CREATED) revert InvalidProjectLifecycle(); 

        projectLifecycle = PROJECT_LIFECYCLE.PROPOSAL;
    }

    function closeProposalsAndOpenVoting() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(projectLifecycle != PROJECT_LIFECYCLE.PROPOSAL) revert InvalidProjectLifecycle(); 
        if(block.timestamp < proposalDeadline) revert ProposalsDurationTooShort();

        projectLifecycle = PROJECT_LIFECYCLE.VOTING;
        votingOpenedTimestamp = block.timestamp;
    }

    //@param _numberOfShortlistedProjects allows users to see how many shortlisted projects the committee will deliberate over. 
    function closeVoting(uint256 _numberOfShortlistedProjects) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(_numberOfShortlistedProjects == 0) revert ZeroAmount();
        if(projectLifecycle != PROJECT_LIFECYCLE.VOTING) revert InvalidProjectLifecycle(); 

        //Shoul i keep the urgent option?
        if(!urgent) {
            if(block.timestamp < votingOpenedTimestamp + projectFactory.minimumVotingDuration()) revert VotingTooShort();
        }

        projectLifecycle = PROJECT_LIFECYCLE.DELIBERATION;
        numberOfShortlistedProjects = _numberOfShortlistedProjects;
    }

    function awardProposal(
        uint256 _proposalId,
        address _projectCommittee
    ) external proposalExists(_proposalId) onlyRole(DEFAULT_ADMIN_ROLE) returns (address projectEscrowInstanceAddr) {

        Proposal memory tempProposal = proposals[_proposalId];
        if(projectLifecycle != PROJECT_LIFECYCLE.DELIBERATION) revert InvalidProjectLifecycle();
        winningProposalId = _proposalId;
        projectLifecycle = PROJECT_LIFECYCLE.AWARDED;

        // This is the safe created by the official with all relevant parties
        _grantRole(PROJECT_COMMITTEE, _projectCommittee);

        projectEscrowInstanceAddr = projectEscrowImplementation.clone();
        projectEscrow = ProjectEscrow(projectEscrowInstanceAddr);
        projectEscrow.initialize(
            tempProposal.fundWallet,
            token,
            _projectCommittee,
            tempProposal.cost
        );

        numberOfTotalMilestones += tempProposal.milestones.length;

        projectFactory.mintInitialSupplyForProject(projectEscrowInstanceAddr, tempProposal.cost);

        if(proposals[_proposalId].depositRequired) {
            _releaseDeposit();
        }
        
    }

    function _completeProject() internal {
        if(projectLifecycle != PROJECT_LIFECYCLE.AWARDED) revert InvalidProjectLifecycle();

        projectLifecycle = PROJECT_LIFECYCLE.COMPLETE;
    }

    function cancelProject(uint256 _settlementAmount) external {
        if(
            projectLifecycle == PROJECT_LIFECYCLE.CANCELLED ||
            projectLifecycle == PROJECT_LIFECYCLE.COMPLETE
        ) revert InvalidProjectLifecycle();

        if(projectLifecycle == PROJECT_LIFECYCLE.AWARDED) {
            _checkRole(PROJECT_COMMITTEE);
            projectEscrow.releaseSettlement(_settlementAmount);
            uint256 leftoverTokens = IPaymentToken(token).balanceOf(address(projectEscrow));
            projectEscrow.cancelProject(leftoverTokens);
            projectFactory.burnProjectTokensFromCancellation(address(projectEscrow), leftoverTokens);
        } else _checkRole(DEFAULT_ADMIN_ROLE);

        cancelledForm = projectLifecycle;
        projectLifecycle = PROJECT_LIFECYCLE.CANCELLED;
    }

    // ----------------------------------------------------------------------------------------------------------
    // ------------------------------------------------>  <------------------------------------------------------
    // ----------------------------------------------------------------------------------------------------------

    function createProposal(
        bytes32 _specContentHash,
        bytes32 _ipfsHash,
        uint256 _cost,
        address _adminWallet,
        address _fundWallet,
        bool _depositRequired,
        Milestone[] memory _milestones
    ) external {
        if(projectLifecycle != PROJECT_LIFECYCLE.PROPOSAL) revert InvalidProjectLifecycle();
        if(block.timestamp > proposalDeadline) revert ProposalDeadlinePassed();
        if(_milestones.length <= 1 || _milestones.length > MAX_MILESTONES) revert InvalidMilestoneCount();
        if(_cost > budgetCap) revert BudgetTooHigh();
        if(_adminWallet == address(0) || _fundWallet == address(0)) revert AddressZero();
        if (
            _specContentHash == bytes32(0) || 
            _ipfsHash == bytes32(0)
        ) revert InvalidHash();

        uint256 totalCost;
        for (uint256 x; x < _milestones.length; x++) {
            Milestone memory localMilestone = _milestones[x];
            if(localMilestone.amount == 0) revert ZeroAmount();
            if(localMilestone.released) revert MilestoneReleased();
            totalCost += localMilestone.amount;
        }
        if(totalCost != _cost) revert MilestonesDontMatchCost();

        proposals[numberOfProposals] = Proposal({
            id: numberOfProposals,
            cost: _cost,
            numberOfMilestonesReleased: 0,
            admin: _adminWallet,
            fundWallet: _fundWallet,
            specContentHash: _specContentHash,
            ipfsHash: _ipfsHash,
            depositRequired: _depositRequired,
            milestones: _milestones
        });

        numberOfProposals++;
    }

    // Votes will be recorded on chain for transparency but also stored off-chain for ease of lookup
    function voteForProposal(uint256 _proposalId) external proposalExists(_proposalId) {
        if(projectLifecycle != PROJECT_LIFECYCLE.VOTING) revert InvalidProjectLifecycle();
        if(hasVoted[msg.sender]) revert UserAlreadyVoted();
        numberOfVotesPerProposal[_proposalId]++;

        hasVoted[msg.sender] = true;

        emit VoteCast(msg.sender, _proposalId);
    }

    // ----------------------------------------------------------------------------------------------------------
    // -----------------------------------------> MILESTONE CHANGES <--------------------------------------------
    // ----------------------------------------------------------------------------------------------------------

    function completeAndReleaseMilestone(bytes32 _evidenceHash) external onlyRole(PROJECT_COMMITTEE) {
        if(projectLifecycle != PROJECT_LIFECYCLE.AWARDED) revert InvalidProjectLifecycle();
        if(_evidenceHash == bytes32(0)) revert InvalidHash();
        _callReleaseAndUpdateStorage(_evidenceHash);

        if(proposals[winningProposalId].numberOfMilestonesReleased == proposals[winningProposalId].milestones.length) {
            _completeProject();
        } 
    }

    function _releaseDeposit() internal {
        _callReleaseAndUpdateStorage(bytes32("Deposit"));
    }

    function _callReleaseAndUpdateStorage(bytes32 _evidenceHash) internal {
        Proposal storage proposal = proposals[winningProposalId];
        Milestone storage milestone = proposal.milestones[proposal.numberOfMilestonesReleased];
        if(milestone.released) revert MilestoneAlreadyReleased();
        proposal.numberOfMilestonesReleased++;
        milestone.released = true;
        milestone.evidenceHash = _evidenceHash;
        projectEscrow.releaseFunds(milestone.amount);
    }

    modifier proposalExists(uint256 _proposalId) {
        if (_proposalId >= numberOfProposals) revert ProposalNonExistent();
        _;
    }

}
