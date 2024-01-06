// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NFTBridge is Ownable {
    struct NFTInfo {
        address nftContract;
        uint256 tokenId;
    }
    mapping (bytes32 => address) initOwnerData;
    mapping (bytes32 => NFTInfo) nftInfos;

    constructor() Ownable(msg.sender) {
    }

    function setOwnerData(bytes32 dataMixedHash, address owner) public onlyOwner {
        initOwnerData[dataMixedHash] = owner;
    }

    function setNFTInfo(bytes32 dataMixedHash, address nftContract, uint256 tokenId) public onlyOwner {
        nftInfos[dataMixedHash] = NFTInfo(nftContract, tokenId);
    }

    function getOwner(bytes32 dataMixedHash) public view returns (address) {
        address owner = initOwnerData[dataMixedHash];
        if (owner == address(0)) {
            owner = IERC721(nftInfos[dataMixedHash].nftContract).ownerOf(nftInfos[dataMixedHash].tokenId);
        }
        return owner;
    }
}