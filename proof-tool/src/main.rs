mod ercmerkle_tree;

use std::fs::File;
use std::io::{BufReader, BufWriter, Read, Write};
use std::os::windows::prelude::FileExt;
use std::path::PathBuf;
use std::time::Instant;
use bytes::{Buf, BufMut, BytesMut};
use clap::{Parser, Subcommand};
use flate2::Compression;
use flate2::read::DeflateDecoder;
use flate2::write::DeflateEncoder;
use crate::ercmerkle_tree::{HashType, hex, MerkleTree, MerkleTreeBuilder};

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
    #[arg(short, long)]
    benchmark: bool,
    #[arg(short, long, default_value = "64")]
    task_size: u64,
    #[arg(short, long)]
    compress: bool,
    #[command(subcommand)]
    command: Subcommands
}

#[derive(Subcommand)]
enum Subcommands {
    Create {
        #[arg(value_name="FILE")]
        file_path: PathBuf,
        #[arg(value_enum, default_value = "keccak256")]
        hash_type: HashType
    },
    Proof {
        #[arg(value_name="FILE")]
        file_path: PathBuf,
        nonce_hash: String,
        #[arg(help = "only for debug")]
        leaf_index: Option<u64>,
    }
}

#[tokio::main]
async fn main() {
    let mut cli = App::parse();
    let mut start = Instant::now();
    match cli.command {
        Subcommands::Create { file_path, hash_type } => {
            let mut file = File::open(&file_path).unwrap();
            let size = file.metadata().unwrap().len();
            println!("calcuting merkle leaf...");
            let mut merkle_builder = MerkleTreeBuilder::new(hash_type);
            loop {
                let mut read_buf = BytesMut::zeroed((1024 * cli.task_size) as usize);
                let readed = file.read(&mut read_buf).unwrap();
                if readed == 0 { break; }
                let mut bufs = Vec::new();

                let leafs = (readed as f64 / 1024f64).ceil() as usize;

                for _ in 0..leafs {
                    bufs.push(read_buf.split_to(1024).freeze());
                }

                merkle_builder.add_leafs(bufs).await;
            }
            if cli.benchmark {
                let dur = Instant::now().duration_since(start).as_secs();
                println!("calcuting leaf speed: {:.2} MB/sec, total use {dur} secs", (size as f64) / 1024f64 / 1024f64 / (dur as f64));
            }

            println!("calcuting merkle tree...");
            start = Instant::now();
            let tree = merkle_builder.calc_tree(size as usize);

            if cli.benchmark {
                let dur = Instant::now().duration_since(start).as_secs();
                let leafs = tree.leaf_size();
                println!("calcuting tree speed: {:.2} leafs/sec, total use {dur} secs", leafs as f64 / (dur as f64));
            }
            println!("save merkle tree...");
            let mut merkle_data = BytesMut::new().writer();
            serde_json::to_writer(&mut merkle_data, &tree.save()).unwrap();
            if cli.compress {
                let file = File::create(file_path.with_extension("merkle.lzma")).unwrap();
                let mut encoder = DeflateEncoder::new(file, Compression::default());
                encoder.write(merkle_data.get_ref()).unwrap();
                encoder.finish().unwrap().flush().unwrap();
            } else {
                std::fs::write(file_path.with_extension("merkle"), merkle_data.get_ref()).unwrap();
            }

            println!("create file root hash 0x{}", hex::encode(tree.get_root()));

        }
        Subcommands::Proof { file_path, nonce_hash , leaf_index } => {
            println!("reading merkle tree...");
            let merkle_data = if cli.compress {

                let mut decoder = DeflateDecoder::new(File::open(file_path.with_extension("merkle")).unwrap());
                let mut data_buf = Vec::new();
                decoder.read_to_end(&mut data_buf).unwrap();
                serde_json::from_slice(&data_buf).unwrap()
            } else {
                serde_json::from_slice(&std::fs::read(file_path.with_extension("merkle")).unwrap()).unwrap()
            };

            let merkle_tree = MerkleTree::load(merkle_data);
            let hash = hex::decode(&nonce_hash.as_str()[2..]).unwrap();

            let mut file = File::open(file_path).unwrap();
            let length = file.metadata().unwrap().len();
            let total_leaf_size = (length as f64 / 1024f64).ceil() as u64;

            let mut min_root: Option<ercmerkle_tree::Hash> = None;
            let mut min_index = None;

            if let Some(i) = leaf_index {
                let mut read_buf = BytesMut::zeroed(1024);
                file.seek_read(&mut read_buf, i * 1024).unwrap();
                let path = merkle_tree.get_path(i);
                let new_leaf: Vec<u8> = read_buf.iter().chain(hash.iter()).map(|v|*v).collect();
                let new_root = merkle_tree.proof_by_path(path, i, &new_leaf);
                //println!("index {} new root {}", i, hex(new_root.as_slice()));
                let _ = min_root.insert(new_root);
                let _ = min_index.insert(i);
            } else {
                println!("finding min index...");
                //let mut read_buf = BytesMut::zeroed((1024 * cli.task_size) as usize);
                let mut i = 0;
                loop {
                    let mut read_buf = BytesMut::zeroed((1024 * cli.task_size) as usize);
                    let readed = file.read(&mut read_buf).unwrap();
                    if readed == 0 { break; }

                    let mut handles = Vec::new();

                    let leafs = (readed as f64 / 1024f64).ceil() as usize;
                    for _ in 0..leafs {
                        let tree = merkle_tree.clone();
                        let mut buf = read_buf.split_to(1024);
                        buf.extend_from_slice(&hash);
                        handles.push(tokio::spawn(async move {
                            (tree.proof_by_path(tree.get_path(i), i, &buf.freeze()), i)
                        }));
                        i += 1;
                    }

                    for handle in handles {
                        let (new_root, index) = handle.await.unwrap();
                        if let Some(root) = min_root {
                            if compare_bytes(new_root.as_slice(), root.as_slice()) < 0 {
                                let _ = min_root.insert(new_root);
                                let _ = min_index.insert(index);
                            }
                        } else {
                            let _ = min_root.insert(new_root);
                            let _ = min_index.insert(index);
                        }
                    }

                }
            }

            println!("found min index {}, min root {}", min_index.unwrap(), hex(min_root.unwrap().as_slice()));
            let paths: Vec<String> = merkle_tree.get_path(min_index.unwrap()).iter().map(|v|hex(v.as_slice())).collect();
            println!("min path [");
            for path in paths {
                println!("\t{},", path)
            }
            println!("]");

            if cli.benchmark {
                let dur = Instant::now().duration_since(start).as_secs();
                println!("create speed: {:.2} MB/sec, total use {dur} secs", (length as f64) / 1024f64 / 1024f64 / (dur as f64));
            }
        }
    }


}
