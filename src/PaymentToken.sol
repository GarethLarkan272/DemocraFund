// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract PaymentToken is ERC20, AccessControl {

    error AddressZero();

    bytes32 public constant FACTORY = keccak256("FACTORY");
    
    constructor(address _admin) ERC20("Generic Example Stable", "GES") {
        if (_admin == address(0)) revert AddressZero();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // Will be called when a proposal is awarded. Sends funds to the escrow contract.
    function mint(address _to, uint256 _amount) external onlyRole(FACTORY) {
        _mint(_to, _amount);
    }

    function burn(address _projectEscrow, uint256 _amount) external onlyRole(FACTORY) {
        _burn(_projectEscrow, _amount);
    }

    function setFactoryRole(address _projectFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_projectFactory == address(0)) revert AddressZero();

        _grantRole(FACTORY, _projectFactory);
    }
}
