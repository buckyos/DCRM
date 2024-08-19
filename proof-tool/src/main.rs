mod ercmerkle_tree;

use std::env::join_paths;
use std::io::{Read, Write};
use std::os::windows::prelude::FileExt;
use std::path::PathBuf;
use clap::{Parser, Subcommand};
use crate::ercmerkle_tree::{calc_hash, HashType, hex, MerkleTree};

fn compare_bytes(a: &[u8], b: &[u8]) -> i32 {
    let n = a.len().min(b.len());

    for i in 0..n {
        if a[i] != b[i] {
            return a[i] as i32 - b[i] as i32;
        }
    }

    return (a.len() - b.len()) as i32;
}


#[derive(Parser)]
struct App {
    #[command(subcommand)]
    command: Subcommands
}

#[derive(Subcommand)]
enum Subcommands {
    Create {
        #[arg(value_name="FILE")]
        file_path: PathBuf,
        #[arg(value_enum)]
        hash_type: HashType
    },
    Proof {
        #[arg(value_name="FILE")]
        file_path: PathBuf,
        nonce_hash: String,

        leaf_index: Option<u64>,
    }
}

fn main() {
    let cli = App::parse();
    match cli.command {
        Subcommands::Create { file_path, hash_type } => {
            let mut file = std::fs::File::open(&file_path).unwrap();
            let size = file.metadata().unwrap().len();
            println!("calcuting merkle tree...");
            let mut merkle_tree = MerkleTree::new(hash_type);
            let mut read_buf = Vec::with_capacity(1024);
            read_buf.resize(1024, 0);
            loop {
                read_buf.fill(0);
                let readed = file.read(&mut read_buf).unwrap();
                if readed == 0 { break; }
                merkle_tree.add_leaf(&read_buf);
            }
            merkle_tree.calc_tree();

            let mut root_hash = merkle_tree.get_root().clone();
            root_hash.as_mut_slice().write(&size.to_be_bytes()).unwrap();
            root_hash.as_mut_slice()[0] &= (1 << 6) - 1;

            match hash_type {
                HashType::Sha256 => {
                    // do nothing
                }
                HashType::Keccak256 => {
                    root_hash.as_mut_slice()[0] |= 1 << 7;
                }
            }

            merkle_tree.update_root(root_hash);

            let merkle_data = merkle_tree.save();
            std::fs::write(file_path.with_extension("merkle"), &serde_json::to_vec(&merkle_data).unwrap()).unwrap();

            println!("create file root hash 0x{}", hex::encode(&root_hash));
        }
        Subcommands::Proof { file_path, nonce_hash , leaf_index } => {
            let merkle_data = serde_json::from_slice(&std::fs::read(file_path.with_extension("merkle")).unwrap()).unwrap();
            let merkle_tree = MerkleTree::load(merkle_data);
            let hash = hex::decode(&nonce_hash.as_str()[2..]).unwrap();

            let file = std::fs::File::open(file_path).unwrap();
            let length = file.metadata().unwrap().len();
            let total_leaf_size = (length as f64 / 1024f64).ceil() as u64;

            let mut min_root: Option<ercmerkle_tree::Hash> = None;
            let mut min_index = None;
            
            let mut read_buf = Vec::with_capacity(1024);
            read_buf.resize(1024, 0);
            if let Some(i) = leaf_index {
                read_buf.fill(0);
                file.seek_read(&mut read_buf, i * 1024).unwrap();
                let path = merkle_tree.get_path(i);
                let new_leaf: Vec<u8> = read_buf.iter().chain(hash.iter()).map(|v|*v).collect();
                let new_root = merkle_tree.proof_by_path(path, i, &new_leaf);
                //println!("index {} new root {}", i, hex(new_root.as_slice()));
                if let Some(root) = min_root {
                    if compare_bytes(new_root.as_slice(), root.as_slice()) < 0 {
                        min_root.insert(new_root);
                        min_index.insert(i);
                    }
                } else {
                    min_root.insert(new_root);
                    min_index.insert(i);
                }
            } else {
                for i in 0..total_leaf_size {
                    read_buf.fill(0);
                    file.seek_read(&mut read_buf, i*1024).unwrap();
                    let path = merkle_tree.get_path(i);
                    let new_leaf: Vec<u8> = read_buf.iter().chain(hash.iter()).map(|v|*v).collect();
                    let new_root = merkle_tree.proof_by_path(path, i, &new_leaf);
                    //println!("index {} new root {}", i, hex(new_root.as_slice()));
                    if let Some(root) = min_root {
                        if compare_bytes(new_root.as_slice(), root.as_slice()) < 0 {
                            min_root.insert(new_root);
                            min_index.insert(i);
                        }
                    } else {
                        min_root.insert(new_root);
                        min_index.insert(i);
                    }
                }
            }


            println!("found min index {}, min root {}", min_index.unwrap(), hex(min_root.unwrap().as_slice()));
            let paths: Vec<String> = merkle_tree.get_path(min_index.unwrap()).iter().map(|v|hex(v.as_slice())).collect();
            println!("min path [");
            for path in paths {
                println!("\t{},", path)
            }
            println!("]")
        }
    }


}
