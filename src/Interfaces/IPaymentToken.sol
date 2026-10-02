// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice The payment token interface used by the factory and the escrow.
///         The factory holds the mint authority via the FACTORY role.
interface IPaymentToken is IERC20 {
    /// @dev Minted straight into a project's escrow at award time.
    function mint(address _to, uint256 _amount) external;
}
