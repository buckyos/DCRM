// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./public_data_storage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract ERC721NFTSelfBridge is IERCPublicDataContract {
    IERC721 public nftAddress;
    address public admin;

    mapping (bytes32 => uint256) hashToTokenId;
    mapping (bytes32 => bool) isInitialized;

    constructor(IERC721 _nftAddress, address _admin, bytes32[] memory dataMixedHash, uint256[] memory tokenId) {
        nftAddress = _nftAddress;
        admin = _admin;
        for (uint i = 0; i < dataMixedHash.length; i++) {
            hashToTokenId[dataMixedHash[i]] = tokenId[i];
            isInitialized[dataMixedHash[i]] = true;
        }
    }

    function setTokenId(bytes32[] calldata dataMixedHash, uint256[] calldata tokenId) public {
        for (uint i = 0; i < dataMixedHash.length; i++) {
            if (msg.sender != admin) {
                require(!isInitialized[dataMixedHash[i]], "Already initialized");
            }

            hashToTokenId[dataMixedHash[i]] = tokenId[i];
            if (!isInitialized[dataMixedHash[i]]) {
                isInitialized[dataMixedHash[i]] = true;
            }
        }
    }

    function getDataOwner(bytes32 dataMixedHash) public view returns (address) {
        return nftAddress.ownerOf(hashToTokenId[dataMixedHash]);
    }

    function getTokenId(bytes32 dataMixedHash) public view returns (uint256, bool) {
        return (hashToTokenId[dataMixedHash], isInitialized[dataMixedHash]);
    }
}