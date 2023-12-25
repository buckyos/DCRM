contract PublicStorageProofDemo {
    struct StoargeProof {
        uint256 nonce_block_high;
        uint256 proof_block;
        uint256 proof_result;
        address prover;
    }
    mapping(bytes32 => StoargeProof) show_datas;

    function showStorageProof(bytes32 dataMixedHash, uint256 nonce_block_high,uint32 index_m, bytes32[] calldata m_path, bytes calldata leafdata) public {
        StoargeProof storage last_proof = show_datas[dataMixedHash];
        // 如果已经存在，判断区块高度差，决定这是一个新的挑战还是对旧的挑战的更新
        bool is_new_show = false;
        
        if(is_new_show) {

        } else {
            // 旧挑战：判断是否结果更好，如果更好，更新结果，并更新区块高度
            require(last_proof.nonce_block_high == nonce_block_high, "nonce_block_high not match");
            uint256 root_hash = _verifyDataProof(dataMixedHash,nonce_block_high,index_m,m_path,leafdata,0);
            require(root_hash > 0, "verify failed");

            if(root_hash < last_proof.proof_result) {
                //根据经济学模型对虚假的proof提供者进行惩罚
                last_proof.proof_result = root_hash;
                last_proof.proof_block = block.number;
                last_proof.prover = msg.sender;
            }
        }

    }

    function _verifyDataProof(bytes32 dataMixedHash,uint256 nonce_block_high, uint32 index, bytes32[] calldata m_path, bytes calldata leafdata,bytes32 noise) private returns(uint256) {
        uint256 nonce = 0;
        uint16 pos = 0;

        //验证leaf_data+index+path 和 dataMixedHash是匹配的,不匹配返回0

        //计算在leaf_data中插入nonce,noise后的root_hash
        
        //返回root_hash
    }

    function showStorageProofWihtPoW(bytes32 dataMixedHash, uint256 nonce_block_high,uint32 index_m, bytes32[] calldata m_path, bytes calldata leafdata,bytes32 noise) public {

    }

}