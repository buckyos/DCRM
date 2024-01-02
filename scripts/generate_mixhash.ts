import { HashType, MerkleTree } from "./ERCMerkleTree";
import fs from "node:fs"
import path from "node:path"
import { ethers } from "hardhat";
export { HashType, MerkleTree } from "./ERCMerkleTree";

export function generateMixHash(filePath: string, type: HashType, treeStorePath: string): Uint8Array {
    let file_op = fs.openSync(filePath, "r");
    let length = fs.statSync(filePath).size;
    let buf = new Uint8Array(1024);
    let begin = 0;
    let tree = new MerkleTree(type);
    while (true) {
        buf.fill(0);
        let n = fs.readSync(file_op, buf);
        if (n == 0) {
            break;
        }
        begin += n;
        tree.addLeaf(buf);
    }
    tree.calcTree();
    let root_hash = tree.getRoot();
  
    //let full_hash =  caclRoot(leaf_hash,type)
    new DataView(root_hash.buffer).setBigUint64(0, BigInt(length), false);

    root_hash[0] &= (1 << 6) - 1;
    switch (type) {
        case HashType.Sha256:
            break;
        case HashType.Keccak256:
            root_hash[0] |= 1 << 7;
            break;
        default:
            throw new Error("unknown hash type");
    }

    fs.writeFileSync(treeStorePath, JSON.stringify(tree.save()));

    return root_hash;
}

function recoverHash(filePath: string, merkle_tree_file: string): Uint8Array {
    let length = fs.statSync(filePath).size;

    let tree = MerkleTree.load(JSON.parse(fs.readFileSync(merkle_tree_file, {encoding: 'utf-8'})));

    let root_hash = tree.getRoot();
  
    //let full_hash =  caclRoot(leaf_hash,type)
    new DataView(root_hash.buffer).setBigUint64(0, BigInt(length), false);

    root_hash[0] &= (1 << 6) - 1;
    switch (tree.type) {
        case HashType.Sha256:
            break;
        case HashType.Keccak256:
            root_hash[0] |= 1 << 7;
            break;
        default:
            throw new Error("unknown hash type");
    }

    return root_hash;
}

export function getSize(mixedHashHex: string): number {
    let mixedHash = ethers.getBytes(mixedHashHex);
    mixedHash[0] &= (1 << 6) - 1;
    let size = new DataView(mixedHash.buffer).getBigUint64(0, false);

    return Number(size);
}