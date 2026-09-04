// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PaymentToken is ERC20 {
    
    constructor() ERC20("Generic Example Stable", "GES") {
      
    }

    // Will be called when a tender is awarded. Sends funds to the escrow contract.
    function mint(address _to, uint256 _amount) external {
      
    }
}
