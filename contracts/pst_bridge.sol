// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./gwt.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PSTBridge is Ownable {
    GWT public gwt;

    mapping(bytes32 => uint256) public pst_to_gwt;

    constructor(address _gwt) Ownable(msg.sender) {
        gwt = GWT(_gwt);
    }

    function getClaimableGWT(string calldata cookie) public view returns (uint256) {
        return pst_to_gwt[keccak256(abi.encodePacked(msg.sender, cookie))];
    }

    function registerPST(address[] calldata recvAddress, string[] calldata cookie, uint256[] calldata pstAmount) onlyOwner public {
        for (uint i = 0; i < recvAddress.length; i++) {
            pst_to_gwt[keccak256(abi.encodePacked(recvAddress[i], cookie[i]))] = pstAmount[i] * (10 ** 18);
        }
    }

    function claimGWT(string calldata cookie) public {
        bytes32 key = keccak256(abi.encodePacked(msg.sender, cookie));
        require(pst_to_gwt[key] > 0, "no GWT amount");
        uint256 gwtAmount = pst_to_gwt[key];
        pst_to_gwt[key] = 0;
        
        gwt.mint(msg.sender, gwtAmount);
    }
}