# prooftool介绍

proof_tool是一个命令行工具，用于构造符合ERC7585的MixHash和存储证明

## Step0. 编译

首先需要安装Rust工具链.

```shell
cd ./proof-tool
cargo build --release
```
随后可以在`./target/release`目录下找到编译好的可执行文件`proof_tool`

## Step1. 得到MixHash

```shell
proof-tool create <FILE> keccak256
```

该命令会返回文件的mixhash，并在<FILE>目录下产生保持了全部merkle tree的文件<FILE>.merkle.输出如下:

```shell
calcuting merkle tree...
create file root hash 0x80000000031e95ed7cbb245c171db93de38f0ca5bc301fdd85537b0fdcdab037
```

## Step2. 产生证明

当生成了<FILE>.merkle，可以基于一个特定的NONCE Block Hash，构造证明

```shell
Running `D:\tmp\rust_build\release\proof_tool.exe proof g:\\backups\\duplicati-b2dae68af7c59429d90bad8d4402665fc.dblock.zip.aes 0x23234545`
```

执行成功能得到调用合约必要的参数，结果如下:

```
found min index 25722, min root 0x000055b73e351bcb244dab5127f7accaa19fa2f5a7db4b1865b4e72dd512388c
min path [
        0x499eede40569bd681abf88af2a983d1f,
        0x2e434db35ec021b901df4b6b27cbd055,
        0x4bd1aa3994d426a623e5a6b8714ad0d0,
        0x3392d19d3d75464cedcb4bbb97374cc5,
        0x0431adce83bc2ba694c1c5db7e9fe5c4,
        0x62f50045a813f6fcd5075af10b7d20a0,
        0xbd2e98f80ef6e654b33b2aa5027a84c3,
        0x62d03e34f4f6715cfe6f7cdf5e926a76,
        0x539225a9b00f225a05e6f5324d78ad4e,
        0xc752be75dbfc102c0bd7b0acb6efc652,
        0x4e375fa210ed5c973eca7b8566b972f0,
        0xd6a3d1a16e513d0c2d16459eb24e1fe8,
        0x2a753be477a7244136442b78f2e595c4,
        0x7577d4f45527b731a0c63740fb64278f,
        0xd8734a25d7d31e2cf3843e88e89c089b,
        0xb4bcb1eca80b2e06eedd510246a1fa32,
]
```

调用合约的参数对应如下:

```solidity
function showData(
    bytes32 dataMixedHash, //0x80000000031e95ed7cbb245c171db93de38f0ca5bc301fdd85537b0fdcdab037
    uint256 nonce_block, //which block'hash is 0x23234545
    uint32 index, //25722
    bytes16[] calldata m_path, //min path
    bytes calldata leafdata,
    ShowType showType
) 
```