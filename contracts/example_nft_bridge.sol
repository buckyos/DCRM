// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./public_data_storage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NFTBridge is IERCPublicDataContract {
    IERC721 nftAddress;

    mapping (bytes32 => uint) hashToTokenId;

    constructor(IERC721 _nftAddress) {
        nftAddress = _nftAddress;
    }

    function addTokenId(bytes32[] calldata dataMixedHash, uint256[] calldata tokenId) public {
        for (uint i = 0; i < dataMixedHash.length; i++) {
            hashToTokenId[dataMixedHash[i]] = tokenId[i];
        }
    }

    function getDataOwner(bytes32 dataMixedHash) public view returns (address) {
        return nftAddress.ownerOf(tokenId);
    }
}