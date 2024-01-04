// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DMCToken is ERC20, Ownable {
    uint256 maxSupply;
    mapping (address => bool) allow_minter;

    modifier onlyMinter() {
        require(allow_minter[msg.sender], "mint not allowed");
        _;
    }

    constructor(uint256 _maxSupply) ERC20("Datamall Chain Token", "DMC") Ownable(msg.sender) {
        maxSupply = _maxSupply;
    }

    function enableMinter(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_minter[addresses[i]] = true;
        }
    }

    function disableMinter(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_minter[addresses[i]] = false;
        }
    }

    function mint(address to, uint256 amount) public onlyMinter {
        require(totalSupply() + amount <= maxSupply, "max supply exceeded");
        _mint(to, amount);
    }
}