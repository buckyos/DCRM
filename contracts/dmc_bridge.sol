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

    function getClaimableDMC2(string calldata cookie) public view returns (uint256) {
        return dmc1_to_dmc2[keccak256(abi.encodePacked(msg.sender, cookie))];
    }

    function registerDMC1(address[] calldata recvAddress, string[] calldata cookie, uint256[] calldata dmc1Amount) onlyOwner public {
        for (uint i = 0; i < recvAddress.length; i++) {
            dmc1_to_dmc2[keccak256(abi.encodePacked(recvAddress[i], cookie[i]))] = dmc1Amount[i];
        }
        
    }

    function claimDMC2(string calldata cookie) public {
        bytes32 key = keccak256(abi.encodePacked(msg.sender, cookie));
        require(dmc1_to_dmc2[key] > 0, "no dmc1 amount");
        uint256 dmc2Amount = dmc1_to_dmc2[key];
        dmc1_to_dmc2[key] = 0;
        
        dmc2.transfer(msg.sender, dmc2Amount);
    }

    function claimRemainDMC2() public onlyOwner {
        dmc2.transfer(msg.sender, dmc2.balanceOf(address(this)));
    }
}