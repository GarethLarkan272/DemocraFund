// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Collector} from "../src/Collector.sol";
import {PaymentToken} from "../src/PaymentToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract CollectorTest is Test {
    Collector public collector;
    PaymentToken public paymentToken;

    address public coinOwner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    function setUp() public {
        paymentToken = new PaymentToken(coinOwner);
        collector = new Collector(address(paymentToken));
    }

    function testConstructorRevertsWithZeroAddress() public {
        vm.expectRevert("Collector: _paymentToken Address Zero");
        new Collector(address(0));
    }

    function testInitialization() public view {
        assertEq(address(collector.paymentToken()), address(paymentToken));
    }

    function testPayFundsWithoutApproval() public {
        uint256 payAmount = 1 ether;
        uint256 currentAllowance = paymentToken.allowance(user1, address(collector));

        vm.startPrank(user1);
        vm.expectRevert(
        abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientAllowance.selector, 
            address(collector), 
            currentAllowance, 
            payAmount
        ));

        collector.payFunds(payAmount);
        vm.stopPrank();
    }

    function testPayFunds() public {
        uint256 mintAmount = 5 ether; // Mint 5 tokens to each user

        vm.startPrank(coinOwner);
        paymentToken.mint(user1, mintAmount);
        paymentToken.mint(user2, mintAmount);
        vm.stopPrank();

        uint256 payAmount = 3 ether; // Each user will pay 3 tokens

        // User1 approves and collects
        vm.startPrank(user1);
        paymentToken.approve(address(collector), payAmount + 1 ether); // Approve more than needed to test exact amount transfer
        collector.payFunds(payAmount);
        vm.stopPrank();

        // User2 approves and collects
        vm.startPrank(user2);
        paymentToken.approve(address(collector), payAmount);
        collector.payFunds(payAmount);
        vm.stopPrank();

        // Verify balances
        assertEq(paymentToken.balanceOf(address(collector)), payAmount * 2);
        assertEq(paymentToken.balanceOf(user1), mintAmount - payAmount);
        assertEq(paymentToken.balanceOf(user2), mintAmount - payAmount);
        assertEq(collector.userTotalPaid(user1), payAmount);
        assertEq(collector.userTotalPaid(user2), payAmount);

        vm.prank(user1);
        collector.payFunds(1 ether); // User1 pays another 1 token

        assertEq(paymentToken.balanceOf(address(collector)), (payAmount * 2) + 1 ether);
        assertEq(paymentToken.balanceOf(user1), mintAmount - payAmount - 1 ether);
        assertEq(collector.userTotalPaid(user1), payAmount + 1 ether);
    }
}