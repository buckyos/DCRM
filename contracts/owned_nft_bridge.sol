// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./public_data_storage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract OwnedNFTBridge is IERCPublicDataContract, Ownable {
    mapping (bytes32 => address) ownerData;

    constructor() Ownable(msg.sender) {
    }

    function setData(bytes32[] calldata dataMixedHash) public onlyOwner {
        for (uint i = 0; i < dataMixedHash.length; i++) {
            ownerData[dataMixedHash[i]] = msg.sender;
        }
    }

    function getDataOwner(bytes32 dataMixedHash) public view returns (address) {
        return ownerData[dataMixedHash];
    }
}