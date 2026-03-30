// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract PaymentToken is ERC20 {

    address public coinOwner;
    
    constructor(address _coinOwner) ERC20("PaymentToken", "SAPT") {
        require(_coinOwner != address(0), "PaymentToken: _coinOwner Address Zero");
        coinOwner = _coinOwner;
    }

    function mint(address _to, uint256 _amount) external {
        require(_to != address(0), "PaymentToken: _to Address Zero");
        require(msg.sender == coinOwner, "PaymentToken: Not Permissioned To Mint");
        _mint(_to, _amount);
    }
}
