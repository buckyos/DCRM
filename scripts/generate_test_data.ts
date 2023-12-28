import { ethers } from "hardhat";
import fs from "node:fs";
import { HashType, generateMixHash } from "./generate_mixhash";

function genTestData() {
    let datas = [];
    let data_num = 10;
    if (!fs.existsSync("testDatas")) {
        fs.mkdirSync("testDatas");
    }
    // 创建10个10K~20K之间的数据
    for (let index = 1; index <= data_num; index++) {
        let data_length = Math.floor(Math.random() * 10240) + 10240;
        let data = ethers.randomBytes(data_length);
        
        let data_file_path = `testDatas/test_data_${index}.bin`;
        let merkle_file_path = `testDatas/test_data_${index}.merkle`;
        fs.writeFileSync(data_file_path, data, {});

        let hash = generateMixHash(data_file_path, HashType.Keccak256, merkle_file_path);

        datas.push({
            data_file_path,
            merkle_file_path,
            hash: ethers.hexlify(hash)
        });
    }
    
    fs.writeFileSync("testDatas/test_data.json", JSON.stringify(datas));
}

genTestData();