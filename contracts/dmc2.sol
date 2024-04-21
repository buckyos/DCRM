// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DMC2 is ERC20Burnable, Ownable {
    uint256 unReleaseSupply;
    mapping (address => bool) allow_minter;

    modifier onlyMinter() {
        require(allow_minter[msg.sender], "mint not allowed");
        _;
    }

    constructor(uint256 _unReleaseSupply, address[] memory initAddress, uint[] memory initAmount) ERC20("Datamall Chain Token", "DMC") Ownable(msg.sender) {
        
        uint256 _totalSupply = _unReleaseSupply;
        for (uint i = 0; i < initAddress.length; i++) {
            _mint(initAddress[i], initAmount[i]);
            _totalSupply -= initAmount[i];
        }

        unReleaseSupply = _totalSupply;
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
        require(unReleaseSupply >= amount, "max supply exceeded");
        _mint(to, amount);
        unReleaseSupply -= amount;
    }
}