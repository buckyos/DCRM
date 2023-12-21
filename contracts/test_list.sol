// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./sortedlist.sol";

contract TestList {
    using SortedScoreList for SortedScoreList.List;
    SortedScoreList.List public list;

    function addScore(bytes32 mixedHash, uint256 score) public {
        list.updateScore(mixedHash, score);
    }

    function getLength() public view returns (uint256) {
        return list.length();
    }

    function getSortedList() public view returns (bytes32[] memory) {
        return list.getSortedList();
    }

    function setMaxLen(uint256 maxLen) public {
        list.setMaxLen(maxLen);
    }

    function maxLen() public view returns (uint256) {
        return list.maxlen();
    }

    function getRanking(bytes32 mixedHash) public view returns (uint256) {
        return list.getRanking(mixedHash);
    }
}