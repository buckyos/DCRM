// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./dmc.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DMCBridge is Ownable {
    DMC public dmc2;

    // DMC1到2的兑换
    mapping(bytes32 => uint256) public dmc1_to_dmc2;

    constructor(address _dmc2) Ownable(msg.sender) {
        dmc2 = DMC(_dmc2);
    }

    function registerDMC1(address recvAddress, string calldata cookie, uint256 dmc1Amount) onlyOwner public {
        dmc1_to_dmc2[keccak256(abi.encodePacked(recvAddress, cookie))] = dmc1Amount;
    }

    function claimDMC2(string calldata cookie) public {
        bytes32 key = keccak256(abi.encodePacked(msg.sender, cookie));
        require(dmc1_to_dmc2[key] > 0, "no dmc1 amount");
        uint256 dmc2Amount = dmc1_to_dmc2[key] * 4 / 5;
        dmc1_to_dmc2[key] = 0;
        
        dmc2.transfer(msg.sender, dmc2Amount);
    }

    function claimRemainDMC2() public onlyOwner {
        dmc2.transfer(msg.sender, dmc2.balanceOf(address(this)));
    }
}