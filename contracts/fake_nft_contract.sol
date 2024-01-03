// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./public_data_storage.sol";

contract FakeNFTContract is IERCPublicDataContract, IERC721VerifyDataHash {
    mapping (uint256 => bytes32) public tokenDataHashes;
    mapping (bytes32 => address) public dataOwners;


    function addData(
        bytes32 dataHash,
        uint256 tokenId
    ) public {
        dataOwners[dataHash] = msg.sender;
        tokenDataHashes[tokenId] = dataHash;
    }

    function getDataOwner(
        bytes32 dataHash
    ) external view override returns (address) {
        return dataOwners[dataHash];
    }

    function tokenDataHash(
        uint256 _tokenId
    ) external view override returns (bytes32) {
        return tokenDataHashes[_tokenId];
    }

    function changeOwner(
        bytes32 dataHash,
        address newOwner
    ) public {
        require(msg.sender == dataOwners[dataHash], "Only owner can change owner");
        dataOwners[dataHash] = newOwner;
    }
}