// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LuckyMint {
    mapping(bytes32 => uint) lucky_mint;

    function getLuckyMint(string calldata cookie, string calldata btcaddr) public view returns(uint) {
        return lucky_mint[keccak256(abi.encodePacked(cookie, btcaddr))];
    }

    function setLuckyMint(string calldata cookie, string calldata btcaddr, uint256 amount) public {
        lucky_mint[keccak256(abi.encodePacked(cookie, btcaddr))] = amount;
    }
}