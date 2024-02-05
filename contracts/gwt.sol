// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./dmc.sol";

contract GWTToken is ERC20Burnable, Ownable {
    mapping (address => bool) allow_transfer;
    mapping (address => bool) allow_minter;

    constructor() ERC20("Gb storage per Week Token", "GWT") Ownable(msg.sender) {
        // enable mint and burn
        allow_transfer[address(0)] = true;
    }

    modifier onlyMinter() {
        require(allow_minter[msg.sender], "mint not allowed");
        _;
    }

    modifier canTransfer(address sender, address to) {
        require(allow_transfer[sender] || allow_transfer[to], "transfer not allowed");
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

    function enableTransfer(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_transfer[addresses[i]] = true;
        }
    }

    function disableTransfer(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_transfer[addresses[i]] = false;
        }
    }

    function mint(address to, uint256 amount) public onlyMinter {
        _mint(to, amount);
    }

    function _update(address sender, address to, uint256 amount) internal override canTransfer(sender, to) {
        super._update(sender, to, amount);
    }

    // only called from contract
    function deductFrom(address spender, uint256 amount) public {
        address sender = msg.sender;
        require(allow_transfer[sender], "not allowed");
        super._transfer(spender, sender, amount);
    }

    function burnFrom(address account, uint256 amount) public override {
        address sender = msg.sender;
        require(allow_minter[sender], "not allowed");
        super._burn(account, amount);
    }
}
