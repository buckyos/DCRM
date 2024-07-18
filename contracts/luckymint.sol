// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LuckyMint contract for DMCs
 * @author weiqiushi@buckyos.com
 * @notice this is a luckymint contract for DMCs, called by our bitcoin inscription backend server
 */

contract LuckyMint is Ownable {
    mapping(bytes32 => uint) lucky_mint;
    address public dataAdmin;

    constructor() Ownable(msg.sender) {
        dataAdmin = msg.sender;
    }

    function setDataAdmin(address _dataAdmin) public onlyOwner {
        dataAdmin = _dataAdmin;
    }

    function getBurnedMintCount(string calldata btcaddr, string calldata cookie) public view returns(uint) {
        return lucky_mint[keccak256(abi.encodePacked(cookie, btcaddr))];
    }

    function setBurnedMintCount(string[] calldata btcaddr, string[] calldata cookie, uint256[] calldata amount) public {
        require(msg.sender == dataAdmin, "not data admin");

        for (uint i = 0; i < btcaddr.length; i++) {
            lucky_mint[keccak256(abi.encodePacked(cookie[i], btcaddr[i]))] = amount[i];
        }
        
    }
}