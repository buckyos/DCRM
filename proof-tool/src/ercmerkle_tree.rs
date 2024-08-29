use std::io::Write;
use std::sync::Arc;
use bytes::{Bytes};
use clap::ValueEnum;
use generic_array::GenericArray;
use generic_array::typenum::{U16, U32};
use sha2::{Sha256, Digest};
use sha3::Keccak256;
use serde::{Deserialize, Serialize};

#[derive(Copy, Clone, PartialEq, Eq, PartialOrd, Ord, ValueEnum, Serialize, Deserialize)]
pub enum HashType {
    Sha256,
    Keccak256,
}

pub type Hash = GenericArray<u8, U32>;
type HalfHash = GenericArray<u8, U16>;

pub fn hex(hash: &[u8]) -> String {
    format!("0x{}", hex::encode(hash))
}

fn decode_hash(hex: &str) -> Hash {
    Hash::from_slice(hex::decode(&hex.as_bytes()[2..]).unwrap().as_slice()).clone()
}

fn decode_half_hash(hex: &str) -> HalfHash {
    HalfHash::from_slice(hex::decode(&hex.as_bytes()[2..]).unwrap().as_slice()).clone()
}

pub fn calc_hash(hash_type: &HashType, data: &[u8]) -> Hash {
    match hash_type {
        HashType::Sha256 => {
            let mut sha256 = Sha256::new();
            sha256.update(data);
            sha256.finalize()
        }
        HashType::Keccak256 => {
            let mut sha3 = Keccak256::new();
            sha3.update(data);
            sha3.finalize()
        }
    }
}

#[derive(Serialize, Deserialize)]
pub struct MerkleTreeData {
    hash_type: HashType,
    tree: Vec<Vec<String>>,
    root: String
}

pub struct MerkleTree {
    tree: Vec<Vec<HalfHash>>,
    root: Hash,
    hash_type: HashType,
}

pub struct MerkleTreeBuilder {
    leaf_hash: Vec<HalfHash>,
    hash_type: HashType,
}

type MerkleTreeStable = Arc<MerkleTree>;

impl MerkleTreeBuilder {
    pub fn new(hash_type: HashType) -> Self {
        Self {
            leaf_hash: vec![],
            hash_type,
        }
    }

    pub fn add_leaf(&mut self, leaf: &[u8]) {
        let hash32 = calc_hash(&self.hash_type, leaf);
        self.leaf_hash.push(HalfHash::from_slice(&hash32.as_slice()[16..]).clone());
    }

    pub async fn add_leafs(&mut self, leafs: Vec<Bytes>) {
        let hash_type = self.hash_type.clone();
        let mut handles = Vec::new();
        for leaf in leafs {
            handles.push(tokio::spawn(async move {
                let hash_type = hash_type.clone();
                let hash32 = calc_hash(&hash_type, &leaf);
                HalfHash::from_slice(&hash32.as_slice()[16..]).clone()
            }))
        }

        for handle in handles {
            self.leaf_hash.push(handle.await.unwrap())
        }
    }

    pub fn calc_tree(self, file_size: usize) -> MerkleTree {
        let mut tree = MerkleTree::new(self.hash_type);
        let mut cur_layer = self.leaf_hash.clone();
        let mut next_layer= Vec::new();
        tree.tree.push(cur_layer.clone());
        let mut hash = Hash::default();
        while cur_layer.len() > 1 {
            for chunk in cur_layer.chunks(2) {
                if chunk.len() == 1 {
                    next_layer.push(chunk[0].clone());
                } else {
                    hash = calc_hash(&self.hash_type, &chunk.concat());
                    next_layer.push(HalfHash::from_slice(&hash.as_slice()[16..]).clone())
                }
            }
            tree.tree.push(next_layer.clone());
            cur_layer = next_layer.clone();
            next_layer.clear();
        }

        hash.as_mut_slice().write(&file_size.to_be_bytes()).unwrap();
        hash.as_mut_slice()[0] &= (1 << 6) - 1;

        match self.hash_type {
            HashType::Sha256 => {
                // do nothing
            }
            HashType::Keccak256 => {
                hash.as_mut_slice()[0] |= 1 << 7;
            }
        }

        tree.root = hash;

        tree
    }
}

impl MerkleTree {
    pub fn new(hash_type: HashType) -> Self {
        Self {
            tree: vec![],
            root: Default::default(),
            hash_type,
        }
    }

    pub fn load(data: MerkleTreeData) -> MerkleTreeStable {
        Arc::new(Self {
            tree: data.tree.iter().map(|v|v.iter().map(|s|decode_half_hash(s)).collect()).collect(),
            root: decode_hash(&data.root),
            hash_type: data.hash_type,
        })
    }

    pub fn save(&self) -> MerkleTreeData {
        MerkleTreeData {
            hash_type: self.hash_type.clone(),
            tree: self.tree.iter().map(|v|v.iter().map(|h|hex(h.as_slice())).collect()).collect(),
            root: hex(self.root.as_slice()),
        }
    }

    pub fn leaf_size(&self) -> usize {
        self.tree[0].len()
    }

    pub fn get_root(&self) -> &Hash {
        &self.root
    }

    pub fn update_root(&mut self, new_root: Hash) {
        self.root = new_root;
    }

    pub fn get_path(&self, index: u64) -> Vec<HalfHash> {
        let mut cur_index = index as usize;
        let mut ret: Vec<HalfHash> = Vec::new();
        for layer in &self.tree {
            if layer.len() < 2 {
                break;
            }

            if cur_index % 2 == 1 {
                ret.push(layer.get(cur_index-1).unwrap().clone());
            } else {
                ret.push(layer.get(cur_index+1).unwrap_or(&HalfHash::default()).clone())
            }

            cur_index = cur_index / 2;
        }

        return ret;
    }

    pub fn proof_by_path(&self, proofs: Vec<HalfHash>, leaf_index: u64, leafdata: &[u8]) -> Hash {
        //println!("check leaf index {}", leaf_index);
        let leaf_hash = calc_hash(&self.hash_type, leafdata);
        let mut current32hash = leaf_hash;
        let mut cur_index = leaf_index;

        for proof in proofs {
            let current16hash = HalfHash::from_slice(&current32hash.as_slice()[16..]).clone();
            if proof.ne(&HalfHash::default()) {
                if cur_index % 2 == 0 {
                    //println!("leaf index {}, proof i at right", cur_index);
                    //println!("calc hash {} + {}", hex(current16hash.as_slice()), hex(proof.as_slice()));
                    current32hash = calc_hash(&self.hash_type, &[current16hash, proof].concat()).into();
                    //println!("\t = {}", hex(current32hash.as_slice()));
                } else {
                    //println!("leaf index {}, proof i at left", cur_index);
                    //println!("calc hash {} + {}", hex(proof.as_slice()), hex(current16hash.as_slice()));
                    current32hash = calc_hash(&self.hash_type, &[proof, current16hash].concat()).into();
                    //println!("\t = {}", hex(current32hash.as_slice()));
                }
            }

            cur_index = cur_index / 2;
        }

        return current32hash;
    }

    pub fn verify(&self, proof: Vec<HalfHash>, leaf_index: u64, leafdata: &[u8]) -> bool {
        let calc_root = self.proof_by_path(proof, leaf_index, leafdata);
        calc_root.eq(&self.root)
    }
}
