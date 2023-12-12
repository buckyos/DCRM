// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract GWTToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("Gb storage per Week Token", "GWT") {
        _mint(msg.sender, initialSupply);
    }
}
