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

        // 这里其实只会去掉最后一个
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

        // 由于max_length有限，这里做两次遍历也并不过多消耗性能
        _deleteScore(self, mixedHash);

        bytes32 currect = self.head;
        bytes32 prev = bytes32(0);
        uint cur_index = 0;
        while (true) {
            // 同score的数据先到先占，这里利用了score的默认值为0的特性，这个循环一定会结束
            if (self.scores[currect] < score) {
                // TODO: 如果插入的数据是最后一个的话，会变成先插入再删除，这里可以优化
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

        // 这里认为，往存储里写一个bytes32 end的值，比遍历要贵
        _ensureSize(self);
    }

    function length(List storage self) public view returns (uint256) {
        // 测试用，判断整个列表长度
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