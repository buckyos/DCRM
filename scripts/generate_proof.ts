import {ethers} from "hardhat"
import { mine } from "@nomicfoundation/hardhat-network-helpers";

import fs from "node:fs"
import path from "node:path"
import { MerkleTree } from "./ERCMerkleTree";
import { compareBytes } from "./ERCMerkleTreeUtil";

export async function generateProof(filepath: string, nonce_block_height: number, treeStorePath: string): Promise<[number, Uint8Array[], Uint8Array, Uint8Array]> {
    console.log("loading merkle tree");
    let tree = MerkleTree.load(JSON.parse(fs.readFileSync(treeStorePath, {encoding: 'utf-8'})));

    let length = fs.statSync(filepath).size;
    let total_leaf_size = Math.ceil(length / 1024);
    let nonce = ethers.getBytes((await ethers.provider.getBlock(nonce_block_height))!.hash!);
    console.log("calc for nonce ", ethers.hexlify(nonce))
    let file_op = fs.openSync(filepath, "r");

    let min_root;
    let min_index;
    for (let index = 0; index < total_leaf_size; index++) {
        let buf = new Uint8Array(1024);
        buf.fill(0);

        fs.readSync(file_op, buf, {position: index * 1024});
        let path = tree.getPath(index);
        let new_root = tree.proofByPath(path, index, new Uint8Array(Buffer.concat([buf, nonce])));
        if (min_root == undefined) {
            min_root = new_root;
            min_index = index;
        } else if (compareBytes(new_root, min_root) < 0) {
            min_root = new_root;
            min_index = index;
        }
    }

    console.log("min index:", min_index);

    let min_leaf = new Uint8Array(1024);
    min_leaf.fill(0);
    fs.readSync(file_op, min_leaf, {position: min_index! * 1024});

    let path = tree.getPath(min_index!);

    return [min_index!, path, min_leaf, min_root!];
}

let test_file_path = "C:\\TDDOWNLOAD\\updateshaoniandream.apk";

async function main(filepath: string) {
    if (!fs.existsSync("merkleData")) {
        fs.mkdirSync("merkleData");
    }
    let merkle_store_path = path.join("merkleData", path.basename(filepath) + ".json");
    await mine();
    let number = await ethers.provider.getBlockNumber()
    let [min_index, noise] = await generateProof(filepath, number, merkle_store_path, false);
    
    console.log("min_index:", min_index, "at block", number);
}

// main(test_file_path).then(() => {process.exit(0);});