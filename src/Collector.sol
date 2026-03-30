// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Collector {
    using SafeERC20 for IERC20;

    IERC20 public paymentToken;

    mapping(address user => uint256 amountPaid) public userTotalPaid;
    
    constructor(address _paymentToken) {
        require(_paymentToken != address(0), "Collector: _paymentToken Address Zero");
        paymentToken = IERC20(_paymentToken);
    }

    function payFunds(uint256 _amount) external {
        uint256 balanceBefore = paymentToken.balanceOf(address(this));
        // User must have approved this address before calling `collectPayment`
        paymentToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        uint256 tokensReceived = paymentToken.balanceOf(address(this)) - balanceBefore;
        require(tokensReceived == _amount, "Collector: Deposit Mismatch");

        userTotalPaid[msg.sender] += tokensReceived;
    }
}
