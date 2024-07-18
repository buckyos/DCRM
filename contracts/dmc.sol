// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DMCX token contract
 * @author weiqiushi@buckyos.com
 * @notice Basically a standard ERC20Burnable contract, add a few modifications to allow certain addresses to mint tokens
 */
contract DMC is ERC20Burnable, Ownable {
    mapping (address => bool) allow_minter;

    modifier onlyMinter() {
        require(allow_minter[msg.sender], "mint not allowed");
        _;
    }

    /**
     * @dev Constructor that gives contract itself and init addresses all of tokens
     * @param _totalSupply Total supply of DMCX tokens, have been minted to contract itself
     * @param initAddress Addresses which will be minted tokens
     * @param initAmount The number of tokens to be minted to each address
     */
    constructor(uint256 _totalSupply, address[] memory initAddress, uint[] memory initAmount) ERC20("Datamall Coin", "DMCX") Ownable(msg.sender) {
        uint256 totalInited = 0;
        for (uint i = 0; i < initAddress.length; i++) {
            _mint(initAddress[i], initAmount[i]);
            totalInited += initAmount[i];
        }
        _mint(address(this), _totalSupply - totalInited);
    }

    /**
     * @dev Only owner can enable addresses to "mint" tokens, usually it will be the exchange contract
     * @param addresses The array of addresses to be enabled as minter
     */

    function enableMinter(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_minter[addresses[i]] = true;
        }
    }

    /**
     * @dev Only owner can disable addresses to "mint" tokens, it may happened when the old exchange contract is replaced by a new one
     * @param addresses The array of addresses to be disabled as minter
     */
    function disableMinter(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_minter[addresses[i]] = false;
        }
    }

    /**
     * @dev It called "mint", but actually it's just transfer tokens from contract itself to the "to" address
     * @dev It ensures that no more token is actually minted than the total supply
     * @param to mint to address
     * @param amount mint amount
     */
    function mint(address to, uint256 amount) public onlyMinter {
        this.transfer(to, amount);
    }
}