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
        // First verify that index in the length range contained in the MixedHash.
        require(index < (lengthFromMixedHash(dataMixedHash) >> 10) + 1, "invalid index");
        
        HashType hashType = hashTypeFromMixedHash(dataMixedHash);

        bytes32 dataHash = _merkleRoot(hashType,m_path,index, _hashLeaf(hashType,leafdata));

        // Compare the last 192 bits only
        require(dataHash & bytes32(uint256((1 << 192) - 1)) == dataMixedHash & bytes32(uint256((1 << 192) - 1)), "mixhash mismatch");

        bytes32 new_root_hash = _merkleRoot(hashType,m_path,index, _hashLeaf(hashType, bytes.concat(leafdata, nonce)));
        bytes32 pow_hash = bytes32(0);

        if(noise != 0) {
            //Enable PoW
            pow_hash = _merkleRoot(hashType,m_path,index, _hashLeaf(hashType, bytes.concat(leafdata, nonce, noise)));
        }

        return (new_root_hash, pow_hash);
    }

    function lengthFromMixedHash(bytes32 dataMixedHash) public pure returns (uint64) {
        return uint64(uint256(dataMixedHash) >> 192 & ((1 << 62) - 1));
    }

    // The first 2 bits of hash represent the hash algorithm，00 = sha256, 10 = keccak256
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
            
            leaf_index = leaf_index / 2;
        }

        return computedHash;
    }

    // sha256 is more expensive than keccak256 because it is not an EVM built-in opcode, but a pre-built internal contract call
    // When hashing 1kb of data, sha256 is costs 160 more than keccak256, and when hashing two bytes32, sha256 is costs 400 more.
    function _merkleRootWithSha256(bytes16[] calldata proof, uint32 leaf_index, bytes16 leaf_hash) internal pure returns (bytes32) {
        bytes16 currentHash = leaf_hash;
        bytes32 computedHash = 0;
        for (uint32 i = 0; i < proof.length; i++) {
            if (proof[i] != bytes32(0)) {
                if (leaf_index % 2 == 0) {
                    computedHash = sha256(bytes.concat(currentHash, proof[i]));
                } else {
                    computedHash = sha256(bytes.concat(proof[i], currentHash));
                }
                currentHash = _bytes32To16(computedHash);
            }
            
            leaf_index = leaf_index / 2;
        }

        return computedHash;
    }
}