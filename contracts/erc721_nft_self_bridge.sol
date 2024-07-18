// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./public_data_storage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ERC721NFTSelfBridge is IERCPublicDataContract, Ownable {
    struct NFTInfo {
        uint256 tokenId;
        address nftAddress;
    }

    mapping (bytes32 => NFTInfo) hashInfo;

    constructor() Ownable(msg.sender) {
    }

    function setTokenId(bytes32[] calldata dataMixedHash, address[] calldata nftAddress, uint256[] calldata tokenId) public {
        for (uint i = 0; i < dataMixedHash.length; i++) {
            if (owner() != _msgSender()) {
                require(hashInfo[dataMixedHash[i]].nftAddress == address(0), "Already initialized");
            }
            require(IERC721(nftAddress[i]).supportsInterface(type(IERC721).interfaceId), "Not ERC721");

            hashInfo[dataMixedHash[i]] = NFTInfo(tokenId[i], nftAddress[i]);
        }
    }

    function getDataOwner(bytes32 dataMixedHash) public view returns (address) {
        NFTInfo memory info = hashInfo[dataMixedHash];
        return IERC721(info.nftAddress).ownerOf(info.tokenId);
    }

    function getTokenId(bytes32 dataMixedHash) public view returns (NFTInfo memory) {
        return hashInfo[dataMixedHash];
    }
}