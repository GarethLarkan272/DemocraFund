// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title PaymentToken
/// @notice The token used to fund project escrows. Designed to behave like a
///         stablecoin (1:1 conceptual peg to fiat, backed by real money held
///         by the paying authority), so swapping in a regulated token or a
///         real payment processor later is a config change, not a rewrite.
/// @dev Mint authority is granted to the factory (the FACTORY role), which
///      mints exactly the awarded budget into each project's escrow at award
///      time. Burn authority sits with the same role; the only intended
///      burner is the Redemption contract (proof-of-burn off-ramp), so supply
///      stays pegged 1:1 to the real-world reserve.
contract PaymentToken is ERC20, AccessControl {
    error AddressZero();

    bytes32 public constant FACTORY = keccak256("FACTORY");

    /// @notice Deploys the token.
    /// @param _admin The deployer's admin; receives DEFAULT_ADMIN_ROLE and is
    ///        the only actor who can later grant the FACTORY role.
    constructor(address _admin) ERC20("Generic Example Stable", "GES") {
        if (_admin == address(0)) revert AddressZero();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /// @notice Mints tokens, called by the factory when a proposal is awarded.
    /// @param _to The project escrow receiving the funding.
    /// @param _amount The awarded budget.
    /// @dev FACTORY role only.
    function mint(address _to, uint256 _amount) external onlyRole(FACTORY) {
        _mint(_to, _amount);
    }

    /// @notice Burns tokens, called by the Redemption contract when a holder
    ///         off-ramps to real money (proof-of-burn).
    /// @param _from The holder whose tokens are destroyed.
    /// @param _amount The amount to burn.
    /// @dev FACTORY role only. Redemption is the only intended burner - this
    ///      is the peg-preserving counterpart to mint.
    function burn(address _from, uint256 _amount) external onlyRole(FACTORY) {
        _burn(_from, _amount);
    }

    /// @notice Grants the FACTORY role to the factory contract.
    /// @param _projectFactory The factory to authorise.
    /// @dev DEFAULT_ADMIN_ROLE only. This is the single wiring step that lets
    ///      the factory mint/burn for projects.
    function setFactoryRole(address _projectFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_projectFactory == address(0)) revert AddressZero();

        _grantRole(FACTORY, _projectFactory);
    }
}
