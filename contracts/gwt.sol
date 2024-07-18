// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DMCX token contract
 * @author weiqiushi@buckyos.com
 * @notice Basically a standard ERC20Burnable contract, add a few modifications to allow certain addresses to mint tokens
 */

contract GWT is ERC20, Ownable {
    mapping (address => bool) allow_minter;

    // GWT token has no supply limit, it represents the total storage space in network
    constructor(address[] memory initAddress, uint[] memory initAmount) ERC20("Gb storage per Week Token", "GWT") Ownable(msg.sender) {
        for (uint i = 0; i < initAddress.length; i++) {
            _mint(initAddress[i], initAmount[i]);
        }
    }

    modifier onlyMinter() {
        require(allow_minter[msg.sender], "mint not allowed");
        _;
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
        _mint(to, amount);
    }
}
