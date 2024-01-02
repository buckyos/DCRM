// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library PublicDataProof {
    enum HashType {
        SHA256,
        RESERVED,
        KECCAK256,
        RESERVED_1
    }

    function calcDataProof(bytes32 dataMixedHash, bytes32 nonce, uint32 index, bytes16[] calldata m_path, bytes calldata leafdata, bytes32 noise) public pure returns(bytes32,bytes32) {
        //先验证index落在MixedHash包含的长度范围内
        require(index < (lengthFromMixedHash(dataMixedHash) >> 10) + 1, "invalid index");

        //验证leaf_data+index+path 和 dataMixedHash是匹配的,不匹配就revert
        
        HashType hashType = hashTypeFromMixedHash(dataMixedHash);

        bytes32 dataHash = _merkleRoot(hashType,m_path,index, _hashLeaf(hashType,leafdata));
        //验证leaf_data+index+path 和 dataMixedHash是匹配的,不匹配就revert
        // 只比较后192位
        require(dataHash & bytes32(uint256((1 << 192) - 1)) == dataMixedHash & bytes32(uint256((1 << 192) - 1)), "mixhash mismatch");

        // 不需要计算插入位置，只是简单的在Leaf的数据后部和头部插入，也足够满足我们的设计目的了？
        bytes32 new_root_hash = _merkleRoot(hashType,m_path,index, _hashLeaf(hashType, bytes.concat(leafdata, nonce)));
        bytes32 pow_hash = bytes32(0);

        if(noise != 0) {
            //Enable PoW
            pow_hash = _merkleRoot(hashType,m_path,index, _hashLeaf(hashType, bytes.concat(leafdata, nonce, noise)));
        }

        return (new_root_hash, pow_hash);
    }

    function lengthFromMixedHash(bytes32 dataMixedHash) public pure returns (uint64) {
        //REVIEW 1<<62是常数，会不会每次都消耗GAS计算？
        return uint64(uint256(dataMixedHash) >> 192 & ((1 << 62) - 1));
    }

    // hash的头2bits表示hash算法，00 = sha256, 10 = keccak256
    function hashTypeFromMixedHash(bytes32 dataMixedHash) public pure returns (HashType) {
        return HashType(uint8(uint256(dataMixedHash) >> 254));
    }

    function _merkleRoot(HashType hashType,bytes16[] calldata proof, uint32 leaf_index,bytes16 leaf_hash) internal pure returns (bytes32) {
        if (hashType == HashType.SHA256) {
            // sha256
            return _merkleRootWithSha256(proof, leaf_index, leaf_hash);
        } else if (hashType == HashType.KECCAK256) {
            // keccak256
            return _merkleRootWithKeccak256(proof, leaf_index, leaf_hash);
        } else {
            revert("invalid hash type");
        }
    }

    function _hashLeaf(HashType hashType,bytes memory leafdata) internal pure returns (bytes16) {
        if (hashType == HashType.SHA256) {
            // sha256
            return _bytes32To16(sha256(leafdata));
        } else if (hashType == HashType.KECCAK256) {
            // keccak256
            return _bytes32To16(keccak256(leafdata));
        } else {
            revert("invalid hash type");
        }
    }

    // from openzeppelin`s MerkleProof.sol
    function _efficientKeccak256(bytes16 a, bytes16 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x10, b)
            value := keccak256(0x00, 0x20)
        }
    }

    function _bytes32To16(bytes32 b) private pure returns (bytes16) {
        return bytes16(uint128(uint256(b)));
    }

    function _merkleRootWithKeccak256(bytes16[] calldata proof, uint32 leaf_index,bytes16 leaf_hash) internal pure returns (bytes32) {
        bytes16 currentHash = leaf_hash;
        bytes32 computedHash = bytes32(0);
        for (uint32 i = 0; i < proof.length; i++) {
            if (proof[i] != bytes32(0)) {
                if (leaf_index % 2 == 0) {
                    computedHash = _efficientKeccak256(currentHash, proof[i]);
                    
                } else {
                    computedHash = _efficientKeccak256(proof[i], currentHash);
                }
                currentHash = _bytes32To16(computedHash);
            }
            
            //require(leaf_index >= 2, "invalid leaf_index");
            leaf_index = leaf_index / 2;
        }

        return computedHash;
    }

    // sha256要比keccak256贵，因为它不是一个EVM内置操作码，而是一个预置的内部合约调用
    // 当hash 1kb数据时，sha256要贵160，当hash 两个bytes32时，sha256要贵400
    function _merkleRootWithSha256(bytes16[] calldata proof, uint32 leaf_index, bytes16 leaf_hash) internal pure returns (bytes32) {
        bytes16 currentHash = leaf_hash;
        bytes32 computedHash = 0;
        for (uint32 i = 0; i < proof.length; i++) {
            if (leaf_index % 2 == 0) {
                computedHash = sha256(bytes.concat(currentHash, proof[i]));
            } else {
                computedHash = sha256(bytes.concat(proof[i], currentHash));
            }
            currentHash = _bytes32To16(computedHash);
            //require(leaf_index >= 2, "invalid leaf_index");
            leaf_index = leaf_index / 2;
        }

        return computedHash;
    }
}