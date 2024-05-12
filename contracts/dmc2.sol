// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DMC2 is ERC20Burnable, Ownable {
    mapping (address => bool) allow_minter;
    bool can_change_minter = true;

    modifier onlyMinter() {
        require(allow_minter[msg.sender], "mint not allowed");
        _;
    }

    constructor(uint256 _totalSupply, address[] memory initAddress, uint[] memory initAmount) ERC20("Datamall Chain Token", "DMC") Ownable(msg.sender) {
        uint256 totalInited = 0;
        for (uint i = 0; i < initAddress.length; i++) {
            _mint(initAddress[i], initAmount[i]);
            totalInited += initAmount[i];
        }
        _mint(address(this), _totalSupply - totalInited);
    }
    
    function disableMinterChange() public onlyOwner {
        can_change_minter = false;
    }

    function enableMinter(address[] calldata addresses) public onlyOwner {
        require(can_change_minter, "mint change not allowed");
        for (uint i = 0; i < addresses.length; i++) {
            allow_minter[addresses[i]] = true;
        }
    }

    function disableMinter(address[] calldata addresses) public onlyOwner {
        require(can_change_minter, "mint change not allowed");
        for (uint i = 0; i < addresses.length; i++) {
            allow_minter[addresses[i]] = false;
        }
    }

    function mint(address to, uint256 amount) public onlyMinter {
        this.transfer(to, amount);
    }
}