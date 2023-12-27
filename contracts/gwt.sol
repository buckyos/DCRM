// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./dmc.sol";

contract GWTToken is ERC20, Ownable {
    DMCToken dmcToken;
    mapping (address => bool) allow_transfer;

    // 这种兑换币，是不是需要设定一个最大上限？
    constructor(address _dmcToken) ERC20("Gb storage per Week Token", "GWT") Ownable(msg.sender) {
        dmcToken = DMCToken(_dmcToken);
    }

    function enableTransfer(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_transfer[addresses[i]] = true;
        }
    }

    function disableTransfer(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_transfer[addresses[i]] = false;
        }
    }

    function _calcGWTAmount(uint256 amount, uint256 remainSupply) internal pure returns(uint256) {
        // 1 : 210
        return amount * 210;
    }

    function _calcDMCAmount(uint256 amount, uint256 remainSupply) internal pure returns(uint256) {
        // 210 : 1
        return amount / 210;
    }

    function _update(address sender, address to, uint256 amount) internal override {
        require(allow_transfer[sender] || allow_transfer[to], "transfer not allowed");
        super._update(sender, to, amount);
    }
}
