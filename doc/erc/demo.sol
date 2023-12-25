// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract PublicStorageProofDemo {
    struct StoargeProof {
        uint256 nonce_block_high;
        uint256 proof_block;
        uint256 proof_result;
        address prover;
    }
    mapping(bytes32 => StoargeProof) show_datas;

    uint256 public constant POW_DIFFICULTY = 4;

    function showStorageProof(bytes32 dataMixedHash, uint256 nonce_block_high,uint32 index_m, bytes32[] calldata m_path, bytes calldata leafdata) public {
        StoargeProof storage last_proof = show_datas[dataMixedHash];
        // 如果已经存在，判断区块高度差，决定这是一个新的挑战还是对旧的挑战的更新
        bool is_new_show = false;

        require(!is_new_show && last_proof.nonce_block_high == nonce_block_high, "nonce_block_high not match");
        uint256 root_hash = _verifyDataProof(dataMixedHash,nonce_block_high,index_m,m_path,leafdata,0);
        
        if(is_new_show) {
            last_proof.nonce_block_high = nonce_block_high;
            last_proof.proof_result = root_hash;
            last_proof.proof_block = block.number;
            last_proof.prover = msg.sender;
        } else {
            // 旧挑战：判断是否结果更好，如果更好，更新结果，并更新区块高度
            if(root_hash < last_proof.proof_result) {
                //根据经济学模型对虚假的proof提供者进行惩罚
                last_proof.proof_result = root_hash;
                last_proof.proof_block = block.number;
                last_proof.prover = msg.sender;
            }
        }
    }

    function merkleProofWithKeccak256(bytes32[] calldata proof, bytes32 leaf_hash) internal returns (bytes32) {;
        return MerkleProof.processProofCalldata(proof, leaf_hash);
    }

    function _efficientHashWithSha256(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        return sha256(bytes.concat(a, b));
    }

    function _hashPairWithSha256(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? _efficientHashWithSha256(a, b) : _efficientHashWithSha256(b, a);
    }

    // sha256要比keccak256贵，因为它不是一个EVM内置操作码，而是一个预置的内部合约调用
    function merkleProofWithSha256(bytes32[] calldata proof, bytes32 leaf_hash) internal returns (bytes32) {
        for (uint256 i = 0; i < proof.length; i++) {
            computedHash = _hashPairWithSha256(computedHash, proof[i]);
        }
        return computedHash;
    }

    function _verifyDataProof(bytes32 dataMixedHash,uint256 nonce_block_high, uint32 index, bytes32[] calldata m_path, bytes calldata leafdata,bytes32 noise) private returns(uint256) {
        require(nonce_block_high < block.number, "invalid nonce_block_high");
        require(block.number - nonce_block_high < 256, "nonce block too old");

        bytes32 nonce = blockhash(nonce_block_high);
        uint16 pos = uint16(uint256(nonce) % 960 + 32);

        // hash的头2bits表示hash算法，00 = sha256, 10 = keccak256
        uint8 hashType = uint8(uint256(dataMixedHash) >> 254);
        bytes32 dataHash;
        if (hashType == 0) {
            // sha256
            dataHash = merkleProofWithSha256(m_path, sha256(leafdata));
        } else if (hashType == 2) {
            // keccak256
            dataHash = merkleProofWithKeccak256(m_path, keccak256(leafdata));
        } else {
            revert("invalid hash type");
        }

        //验证leaf_data+index+path 和 dataMixedHash是匹配的,不匹配就revert
        // 只比较后192位
        require(dataHash & bytes32(uint256(1 << 192 - 1)) == dataMixedHash & bytes32(uint256(1 << 192 - 1)), "data hash mismatch");

        //计算在leaf_data中插入nonce,noise后的root_hash
        bytes32 new_root_hash;
        bytes memory new_leafdata = bytes.concat(leafdata[:pos], nonce, noise, leafdata[pos:]);
        if (hashType == 0) {
            // sha256
            new_root_hash = merkleProofWithSha256(m_path, sha256(new_leafdata));
        } else if (hashType == 2) {
            // keccak256
            new_root_hash = merkleProofWithKeccak256(m_path, keccak256(new_leafdata));
        } else {
            revert("invalid hash type");
        }

        //返回root_hash
        return new_root_hash;
    }

    function showStorageProofWihtPoW(bytes32 dataMixedHash, uint256 nonce_block_high,uint32 index_m, bytes32[] calldata m_path, bytes calldata leafdata,bytes32 noise) public {
        StoargeProof storage last_proof = show_datas[dataMixedHash];
        // 如果已经存在，判断区块高度差，决定这是一个新的挑战还是对旧的挑战的更新
        bool is_new_show = false;

        require(!is_new_show && last_proof.nonce_block_high == nonce_block_high, "nonce_block_high not match");
        uint256 root_hash = _verifyDataProof(dataMixedHash,nonce_block_high,index_m,m_path,leafdata,noise);

        // 判断新的root_hash是否满足pow难度,判断方法为后N个bits是否为0
        require(root_hash & (1 << POW_DIFFICULTY - 1) == 0, "pow difficulty not match");
        
        if(is_new_show) {
            last_proof.nonce_block_high = nonce_block_high;
            last_proof.proof_result = root_hash;
            last_proof.proof_block = block.number;
            last_proof.prover = msg.sender;
        } else {
            // 旧挑战：判断是否结果更好，如果更好，更新结果，并更新区块高度
            if(root_hash < last_proof.proof_result) {
                //根据经济学模型对虚假的proof提供者进行惩罚
                last_proof.proof_result = root_hash;
                last_proof.proof_block = block.number;
                last_proof.prover = msg.sender;
            }
        }
    }

}