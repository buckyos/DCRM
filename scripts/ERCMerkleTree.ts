import { ethers } from 'hardhat';
import { Buffer } from "node:buffer";
import { equalsBytes } from './ERCMerkleTreeUtil';

export enum HashType {
    Sha256,
    Keccak256,
}

export function calcHash(buf: Uint8Array, type: HashType): Uint8Array {
    let ret = type == HashType.Sha256 ? ethers.sha256(buf) : ethers.keccak256(buf);

    return ethers.getBytes(ret);
}

export interface MerkleTreeData {
    type: HashType;
    tree: string[][];
    root: string;
}

const ZERO_BYTES16 = ethers.getBytes(ethers.ZeroHash).slice(16);

export class MerkleTree {
    private leaf_hash: Uint8Array[] = [];
    private tree: Uint8Array[][] = [];
    private root: Uint8Array = new Uint8Array(32);
    constructor(public type: HashType) {

    }

    static load(data: MerkleTreeData): MerkleTree {
        let ret = new MerkleTree(data.type);
        ret.tree = data.tree.map((layer) => layer.map((v) => ethers.getBytes(v)));
        ret.root = ethers.getBytes(data.root);
        return ret;
    }

    addLeaf(leaf: Uint8Array) {
        this.leaf_hash.push(calcHash(leaf, this.type).slice(16));
    }

    calcTree() {
        let cur_layer = this.leaf_hash;
        this.tree.push(cur_layer);
        let hash = new Uint8Array(32);
        while (cur_layer.length > 1) {
            let next_layer = [];
            for (let i = 0; i < cur_layer.length; i += 2) {
                if (i == cur_layer.length - 1) {
                    next_layer.push(cur_layer[i]);
                } else {
                    hash = calcHash(new Uint8Array(Buffer.concat([cur_layer[i], cur_layer[i + 1]])), this.type);
                    next_layer.push(hash.slice(16));
                }
            }
            cur_layer = next_layer;
            this.tree.push(cur_layer);
        }

        this.root = hash;
    }

    getRoot(): Uint8Array {
        return this.root;
    }

    getPath(index: number): Uint8Array[] {
        let ret = [];
        for (let layer = 0; layer < this.tree.length - 1; layer++) {
            if (index % 2 == 1) {
                ret.push(this.tree[layer][index - 1]);
            } else {
                ret.push(this.tree[layer][index + 1] || ZERO_BYTES16);
            }
            index = Math.floor(index / 2);
        }

        return ret;
    }

    save(): MerkleTreeData {
        return {
            type: this.type,
            tree: this.tree.map((layer) => layer.map(ethers.hexlify)),
            root: ethers.hexlify(this.getRoot()),
        };
    }

    proofByPath(proof: Uint8Array[], leaf_index: number, leafdata: Uint8Array): Uint8Array {
        let leaf_hash = calcHash(leafdata, this.type);
        let currentHash = leaf_hash;
        for (let i = 0; i < proof.length; i++) {
            if (currentHash.length == 32) {
                currentHash = currentHash.slice(16);
            }
            
            if (!equalsBytes(proof[i], ZERO_BYTES16)) {
                if (leaf_index % 2 == 0) {
                    currentHash = calcHash(new Uint8Array(Buffer.concat([currentHash, proof[i]])), this.type);
                } else {
                    currentHash = calcHash(new Uint8Array(Buffer.concat([proof[i], currentHash])), this.type);
                }
            }
            
            leaf_index = Math.floor(leaf_index / 2);
        }

        return currentHash;
    }

    verify(proof: Uint8Array[], leaf_index: number, leafdata: Uint8Array): boolean {
        let calc_root = this.proofByPath(proof, leaf_index, leafdata);
        return equalsBytes(calc_root, this.getRoot());
    }
}
