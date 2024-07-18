// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library SortedScoreList {
    struct List {
        uint256 max_length;
        bytes32 head;
        mapping(bytes32 => uint256) scores;
        mapping(bytes32 => bytes32) sorted;
    }

    function _ensureSize(List storage self) private {
        uint32 cur_length = 0;
        bytes32 current = self.head;
        bytes32 prev = current;
        while (cur_length < self.max_length && current != bytes32(0)) {
            cur_length += 1;
            prev = current;
            current = self.sorted[current];
        }

        // Only the last one will be removed here
        if (current != bytes32(0)) {
            self.sorted[prev] = bytes32(0);
            delete self.scores[current];
            delete self.sorted[current];
        }
    }

    function _deleteScore(List storage self, bytes32 mixedHash) private  {
        if (self.head == mixedHash) {
            self.head = self.sorted[mixedHash];
            delete self.sorted[mixedHash];
            delete self.scores[mixedHash];
        } else {
            bytes32 current = self.head;
            bytes32 next = self.sorted[current];
            while (next != bytes32(0)) {
                if (next == mixedHash) {
                    self.sorted[current] = self.sorted[next];
                    delete self.sorted[next];
                    delete self.scores[next];
                    return;
                }
                current = next;
                next = self.sorted[current];
            }
        }
    }

    function updateScore(List storage self, bytes32 mixedHash, uint256 score) public {
        if (self.scores[mixedHash] == score) {
            return;
        }

        // Since max_length is limited, doing two traversals here doesn't cost so much gas.
        _deleteScore(self, mixedHash);

        bytes32 currect = self.head;
        bytes32 prev = bytes32(0);
        uint cur_index = 0;
        while (true) {
            // since the default value of uint256 is 0, the loop will surely end
            if (self.scores[currect] < score) {
                if (prev != bytes32(0)) {
                    self.sorted[prev] = mixedHash;
                }
                self.sorted[mixedHash] = currect;
                self.scores[mixedHash] = score;
                break;
            }
            cur_index += 1;
            prev = currect;
            currect = self.sorted[currect];
        }

        if (cur_index == 0) {
            self.head = mixedHash;
        }

        // I think that writing a bytes32 to storage is expensive than traversing the data
        _ensureSize(self);
    }

    function length(List storage self) public view returns (uint256) {
        uint32 cur_length = 0;
        bytes32 current = self.head;
        while (current != bytes32(0)) {
            cur_length += 1;
            current = self.sorted[current];
        }

        return cur_length;
    }

    function getSortedList(List storage self) public view returns (bytes32[] memory) {
        bytes32[] memory sortedList = new bytes32[](self.max_length);
        uint256 cur = 0;
        bytes32 current = self.head;
        while (current != bytes32(0)) {
            sortedList[cur] = current;
            cur += 1;
            current = self.sorted[current];
        }

        return sortedList;
    }

    function getRanking(List storage self, bytes32 mixedHash) public view returns (uint256) {
        uint256 ranking = 1;
        bytes32 current = self.head;
        while (current != bytes32(0)) {
            if (current == mixedHash) {
                return ranking;
            }
            ranking += 1;
            current = self.sorted[current];
        }
        return 0;
    }

    function setMaxLen(List storage self, uint256 max_length) public {
        require(max_length > self.max_length, "max_length must be greater than current max_length");
        self.max_length = max_length;
    }

    function maxlen(List storage self) public view returns (uint256) {
        return self.max_length;
    }

    function exists(List storage self, bytes32 mixedHash) public view returns (bool) {
        return self.scores[mixedHash] > 0;
    }
}