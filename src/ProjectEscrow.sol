// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPaymentToken} from "./Interfaces/IPaymentToken.sol";



contract ProjectEscrow is Initializable {

    using SafeERC20 for IPaymentToken;

    // Deposit will always be the first milestone

    uint256 public totalProjectBudget;
    uint256 public totalReleased;
    uint256 public totalBurnedDueToCancellation;
    uint256 public settlementPaid;

    bool public cancelled;

    address public projectWallet;
    address public projectGovernanceContract;

    IPaymentToken public token;

    error MilestoneAlreadyReleased();
    error AccountingMismatch();
    error AddressZero();
    error ZeroBudget();
    error ProjectCancelled();
    error SettlementTooHigh();
    error UnauthorisedCalled();

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _projectWallet,
        address _token,
        address _projectCommittee,
        uint256 _totalProjectBudget
    ) external initializer {

        if(
            _projectWallet == address(0) ||
            _token == address(0) ||
            _projectCommittee == address(0)
        ) revert AddressZero();

        if (_totalProjectBudget == 0) revert ZeroBudget();

        totalProjectBudget = _totalProjectBudget;
        token = IPaymentToken(_token);
        projectWallet = _projectWallet;
        projectGovernanceContract = msg.sender;
    }

    function releaseFunds(uint256 _amount) external onlyGovernanceContract projectOpen {
        token.safeTransfer(projectWallet, _amount);
        totalReleased += _amount;
        if(token.balanceOf(address(this)) < totalProjectBudget - totalReleased) revert AccountingMismatch();
    }

    function releaseSettlement(uint256 _settlementAmount) external onlyGovernanceContract projectOpen {
        // Deducting settlementPaid here just incase in future their is a double settlement payment
        if(_settlementAmount > totalProjectBudget - totalReleased - settlementPaid) revert SettlementTooHigh();
        token.safeTransfer(projectWallet, _settlementAmount);
        settlementPaid += _settlementAmount;
    }

    function cancelProject(
        uint256 _leftoverTokens
    ) external onlyGovernanceContract projectOpen {
        totalBurnedDueToCancellation = _leftoverTokens;
        cancelled = true;
    }

    modifier projectOpen() {
        if(cancelled) revert ProjectCancelled();
        _;
    }

    modifier onlyGovernanceContract() {
        if(msg.sender != projectGovernanceContract) revert UnauthorisedCalled();
        _;
    }
}