// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LuckyMint {
    mapping(bytes32 => uint) lucky_mint;

    function getBurnedMintCount(string calldata btcaddr, string calldata cookie) public view returns(uint) {
        return lucky_mint[keccak256(abi.encodePacked(cookie, btcaddr))];
    }

    function setBurnedMintCount(string calldata btcaddr, string calldata cookie, uint256 amount) public {
        lucky_mint[keccak256(abi.encodePacked(cookie, btcaddr))] = amount;
    }
}