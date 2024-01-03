import {ethers} from "hardhat"
import fs from "node:fs"
import { MerkleTree } from "./ERCMerkleTree";
import { compareBytes } from "./ERCMerkleTreeUtil";

export async function genProofByIndex(filepath: string, index: number, treeStorePath: string): Promise<[number, Uint8Array[], Uint8Array, Uint8Array]> {
    let tree = MerkleTree.load(JSON.parse(fs.readFileSync(treeStorePath, {encoding: 'utf-8'})));
    let file_op = fs.openSync(filepath, "r");

    let buf = new Uint8Array(1024);
    buf.fill(0);

    fs.readSync(file_op, buf, {position: index * 1024});
    let path = tree.getPath(index);

    return [index, path, buf, tree.proofByPath(path, index, buf)];
}

export async function generateProof(filepath: string, nonce_block_height: number, treeStorePath: string): Promise<[number, Uint8Array[], Uint8Array, Uint8Array]> {
    let tree = MerkleTree.load(JSON.parse(fs.readFileSync(treeStorePath, {encoding: 'utf-8'})));

    let length = fs.statSync(filepath).size;
    let total_leaf_size = Math.ceil(length / 1024);
    let nonce = ethers.getBytes((await ethers.provider.getBlock(nonce_block_height))!.hash!);
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

    let min_leaf = new Uint8Array(1024);
    min_leaf.fill(0);
    fs.readSync(file_op, min_leaf, {position: min_index! * 1024});

    let path = tree.getPath(min_index!);

    return [min_index!, path, min_leaf, min_root!];
}