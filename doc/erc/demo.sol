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

    uint256 sysConfigShowTimeout = 640;
    uint256 public constant POW_DIFFICULTY = 4;

    function showStorageProof(bytes32 dataMixedHash, uint256 nonce_block_high,uint32 index_m, bytes16[] calldata m_path, bytes calldata leafdata) public {
        StoargeProof storage last_proof = show_datas[dataMixedHash];
        // 如果已经存在，判断区块高度差，决定这是一个新的挑战还是对旧的挑战的更新
        bool is_new_show = false;
        if(last_proof.proof_block == 0) {
            is_new_show = true;
        } else {
            if (block.number - last_proof.proof_block > sysConfigShowTimeout){
                //Last Show Proof successed!
                //TODO:根据经济学模型对上一个Proof的提供者进行奖励
                last_proof.proof_block = 0;
                is_new_show = true;
            } 
        } 
    
        require(!is_new_show && last_proof.nonce_block_high == nonce_block_high, "nonce_block_high not match");
        (bytes32 root_hash,) = _verifyDataProof(dataMixedHash,nonce_block_high,index_m,m_path,leafdata,0);
        
        if(is_new_show) {
            last_proof.nonce_block_high = nonce_block_high;
            last_proof.proof_result = uint256(root_hash);
            last_proof.proof_block = block.number;
            last_proof.prover = msg.sender;
        } else {
            // 已经有挑战存在：判断是否结果更好，如果更好，更新结果，并更新区块高度
            if(uint256(root_hash) < last_proof.proof_result) {
                //TODO:根据经济学模型对虚假的proof提供者进行惩罚
                last_proof.proof_result = uint256(root_hash);
                last_proof.proof_block = block.number;
                last_proof.prover = msg.sender;
            } 
        }
    }


    function showStorageProofWihtPoW(bytes32 dataMixedHash, uint256 nonce_block_high,uint32 index_m, bytes16[] calldata m_path, bytes calldata leafdata,bytes32 noise) public {
        StoargeProof storage last_proof = show_datas[dataMixedHash];
        // 如果已经存在，判断区块高度差，决定这是一个新的挑战还是对旧的挑战的更新
        bool is_new_show = false;
        if(last_proof.proof_block == 0) {
            is_new_show = true;
        } else {
            if (block.number - last_proof.proof_block > sysConfigShowTimeout){
                //Last Show Proof successed!
                //TODO:根据经济学模型对上一个Proof的提供者进行奖励
                last_proof.proof_block = 0;
                is_new_show = true;
            } 
        }

        require(!is_new_show && last_proof.nonce_block_high == nonce_block_high, "nonce_block_high not match");
        (bytes32 root_hash,bytes32 pow_hash) = _verifyDataProof(dataMixedHash,nonce_block_high,index_m,m_path,leafdata,0);
        // 判断新的root_hash是否满足pow难度,判断方法为后N个bits是否为0
        require(uint256(pow_hash) & (1 << POW_DIFFICULTY - 1) == 0, "pow difficulty not match");
        
        if(is_new_show) {
            last_proof.nonce_block_high = nonce_block_high;
            last_proof.proof_result = uint256(root_hash);
            last_proof.proof_block = block.number;
            last_proof.prover = msg.sender;
        } else {
            // 旧挑战：判断是否结果更好，如果更好，更新结果，并更新区块高度
            if(uint256(root_hash) < last_proof.proof_result) {
                //根据经济学模型对虚假的proof提供者进行惩罚
                last_proof.proof_result = uint256(root_hash);
                last_proof.proof_block = block.number;
                last_proof.prover = msg.sender;
            }
        }
    }
    
    function _verifyDataProof(bytes32 dataMixedHash,uint256 nonce_block_high, uint32 index, bytes16[] calldata m_path, bytes calldata leafdata,bytes32 noise) private view returns(bytes32,bytes32) {
        require(nonce_block_high < block.number, "invalid nonce_block_high");
        require(block.number - nonce_block_high < 256, "nonce block too old");

        bytes32 nonce = blockhash(nonce_block_high);
        uint16 pos = uint16(uint256(nonce) % 960 + 32);

        //REVIEW: 应该先验证index落在MixedHash包含的长度范围内

        //验证leaf_data+index+path 和 dataMixedHash是匹配的,不匹配就revert
        // hash的头2bits表示hash算法，00 = sha256, 10 = keccak256
        uint8 hashType = uint8(uint256(dataMixedHash) >> 254);
        bytes32 dataHash;
        if (hashType == 0) {
            // sha256
            dataHash = _merkleRootWithSha256(m_path, index, bytes16(sha256(leafdata)));
        } else if (hashType == 2) {
            // keccak256
            dataHash = _merkleRootWithKeccak256(m_path, index, bytes16(keccak256(leafdata)));
        } else {
            revert("invalid hash type");
        }

        //验证leaf_data+index+path 和 dataMixedHash是匹配的,不匹配就revert
        // 只比较后192位
        require(dataHash & bytes32(uint256(1 << 192 - 1)) == dataMixedHash & bytes32(uint256(1 << 192 - 1)), "mixhash mismatch");

        //计算在leaf_data中插入nonce,noise后的root_hash
        bytes memory new_leafdata;
        if(noise != 0) {
            //Enable PoW
            new_leafdata = bytes.concat(leafdata[:pos], nonce);
            bytes32 new_root_hash = _merkleRoot(hashType,m_path,index, _hashLeaf(hashType,new_leafdata));
            new_leafdata = bytes.concat(leafdata[:pos], nonce, noise, leafdata[pos:]);

            return (new_root_hash,_merkleRoot(hashType,m_path,index, _hashLeaf(hashType,new_leafdata)));
        } else {
            //Disable PoW
            new_leafdata = bytes.concat(leafdata[:pos], nonce);
            return (_merkleRoot(hashType,m_path,index, _hashLeaf(hashType,new_leafdata)),0);
        }
    }

    function _merkleRoot(uint8 hashType,bytes16[] calldata proof, uint32 leaf_index,bytes16 leaf_hash) internal pure returns (bytes32) {
        if (hashType == 0) {
            // sha256
            return _merkleRootWithSha256(proof, leaf_index, leaf_hash);
        } else if (hashType == 2) {
            // keccak256
            return _merkleRootWithKeccak256(proof, leaf_index, leaf_hash);
        } else {
            revert("invalid hash type");
        }
    }

    function _hashLeaf(uint8 hashType,bytes memory leafdata) internal pure returns (bytes16) {
        if (hashType == 0) {
            // sha256
            return bytes16(sha256(leafdata));
        } else if (hashType == 2) {
            // keccak256
            return bytes16(keccak256(leafdata));
        } else {
            revert("invalid hash type");
        }
    }

    function _merkleRootWithKeccak256(bytes16[] calldata proof, uint32 leaf_index,bytes16 leaf_hash) internal pure returns (bytes32) {
        bytes16 currentHash = leaf_hash;
        bytes32 computedHash = 0;
        for (uint32 i = 0; i < proof.length; i++) {
            if (leaf_index % 2 == 0) {
                //sha256(bytes.concat(a, b))?
                computedHash = keccak256(abi.encodePacked(currentHash, proof[i]));
            } else {
                computedHash = keccak256(abi.encodePacked(proof[i], currentHash));
            }
            currentHash = bytes16(computedHash);
            require(leaf_index >= 2, "invalid leaf_index");
            leaf_index = leaf_index / 2;
        }

        return computedHash;
    }

    // sha256要比keccak256贵，因为它不是一个EVM内置操作码，而是一个预置的内部合约调用
    // REVIEW:要贵多少？
    function _merkleRootWithSha256(bytes16[] calldata proof, uint32 leaf_index, bytes16 leaf_hash) internal pure returns (bytes32) {
        bytes16 currentHash = leaf_hash;
        bytes32 computedHash = 0;
        for (uint32 i = 0; i < proof.length; i++) {
            if (leaf_index % 2 == 0) {
                //sha256(bytes.concat(a, b))?
                computedHash = sha256(abi.encodePacked(currentHash, proof[i]));
            } else {
                computedHash = sha256(abi.encodePacked(proof[i], currentHash));
            }
            currentHash = bytes16(computedHash);
            require(leaf_index >= 2, "invalid leaf_index");
            leaf_index = leaf_index / 2;
            
        }

        return computedHash;
    }
}