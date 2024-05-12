// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GWTToken2 is ERC20, Ownable {
    mapping (address => bool) allow_minter;
    bool can_change_minter = true;

    constructor() ERC20("Gb storage per Week Token", "GWT") Ownable(msg.sender) {
        //给owner分配5000万Token 
        _mint(msg.sender, 50000000 * 10 ** uint(decimals()));
    }

    modifier onlyMinter() {
        require(allow_minter[msg.sender], "mint not allowed");
        _;
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
        _mint(to, amount);
    }
}
