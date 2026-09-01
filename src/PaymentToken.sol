// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract HumewoodZAR is ERC20 {
    
    constructor() ERC20("Humewood ZAR", "HUME") {
      
    }

    // Will be called when a tender is awarded. Sends funds to the escrow contract.
    function mint(address _to, uint256 _amount) external {
      
    }
}
