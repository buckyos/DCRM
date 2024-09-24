// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./public_data_storage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract PublicDataNFTWithMeta is IERCPublicDataContract, ERC721, Ownable {
    using Strings for uint256;

    mapping (bytes32 => string) private dataMetas;

    mapping (address => bool) private writer;

    string private baseURI;

    modifier onlyWriter() {
        require(writer[msg.sender], "not writer");
        _;
    }

    constructor(string memory _name, string memory _symbol, string memory _baseURI) Ownable(msg.sender) ERC721(_name, _symbol) {
        baseURI = _baseURI;
        writer[msg.sender] = true;
    }

    function setData(bytes32[] calldata dataMixedHash, address[] calldata owners, string[] calldata _dataMetas) public onlyWriter {
        require(dataMixedHash.length == owners.length, "invalid data length");
        require(dataMixedHash.length == _dataMetas.length, "invalid data length");
        
        for (uint i = 0; i < dataMixedHash.length; i++) {
            _mint(owners[i], uint256(dataMixedHash[i]));
            dataMetas[dataMixedHash[i]] = _dataMetas[i];
        }
    }

    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }

    function enableWriter(address[] calldata _writers) public onlyOwner {
        for (uint i = 0; i < _writers.length; i++) {
            writer[_writers[i]] = true;
        }
    }

    function disableWriter(address[] calldata _writers) public onlyOwner {
        for (uint i = 0; i < _writers.length; i++) {
            writer[_writers[i]] = false;
        }
    }

    function getDataOwner(bytes32 dataMixedHash) public view returns (address) {
        return ownerOf(uint256(dataMixedHash));
    }

    function getDataMeta(bytes32 dataMixedHash) public view returns (string memory) {
        return dataMetas[dataMixedHash];
    }

    function tokenURI(bytes32 tokenId) public view returns (string memory) {
        return tokenURI(uint256(tokenId));
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(uint256(tokenId));

        return bytes(baseURI).length > 0 ? string.concat(baseURI, tokenId.toHexString(32)) : "";
    }

    function approve(address to, bytes32 tokenId) public {
        approve(to, uint256(tokenId));
    }

    function getApproved(bytes32 tokenId) public view returns (address) {
        return getApproved(uint256(tokenId));
    }

    function transferFrom(address from, address to, bytes32 tokenId) public {
        transferFrom(from, to, uint256(tokenId));
    }

    function safeTransferFrom(address from, address to, bytes32 tokenId) public {
        safeTransferFrom(from, to, uint256(tokenId));
    }

    function safeTransferFrom(address from, address to, bytes32 tokenId, bytes memory data) public {
        safeTransferFrom(from, to, uint256(tokenId), data);
    }

    function burn(bytes32 tokenId) public {
        require(getDataOwner(tokenId) == msg.sender || writer[msg.sender], "not owner or writer");
        _burn(uint256(tokenId));
    }
}