---
title: 一种支持链下数据存储证明的Hash算法 （或则存储证明）
description: 在默克尔树的根Hash上进行升级，让保存在链上的数据Hash可以通过对应的密码学流程和简单的博弈流程提高其数据的可用性和可靠性。
author: Liu Zhicong,waterflier
discussions-to: <URL>
status: Draft
type: <Standards Track, Meta, or Informational>
category: ERC # Only required for Standards Track. Otherwise, remove this field.
created: 2023-12-21
requires: 721,1155 # Only required when you reference an EIP in the `Specification` section. Otherwise, remove this field.
---


## Abstract


什么是存储证明
本文提出的存储证明结构的基础设计
新的存储证明的好处
本文建议
本文还建议对ERC721和ERC1155进行必要的扩展

<!--
  The Abstract is a multi-sentence (short paragraph) technical summary. This should be a very terse and human-readable version of the specification section. Someone should be able to read only the abstract to get the gist of what this specification does.

  TODO: Remove this comment before submitting
-->

## Motivation
最后写，内容是存储证明的发展和迫切需要解决的问题
<!--
  This section is optional.

  The motivation section should include a description of any nontrivial problems the EIP solves. It should not describe how the EIP solves those problems, unless it is not immediately obvious. It should not describe why the EIP should be made into a standard, unless it is not immediately obvious.

  With a few exceptions, external links are not allowed. If you feel that a particular resource would demonstrate a compelling case for your EIP, then save it as a printer-friendly PDF, put it in the assets folder, and link to that copy.

  TODO: Remove this comment before submitting
-->

## Specification
The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.


<!--
  The Specification section should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for any of the current Ethereum platforms (besu, erigon, ethereumjs, go-ethereum, nethermind, or others).

  It is recommended to follow RFC 2119 and RFC 8170. Do not remove the key word definitions if RFC 2119 and RFC 8170 are followed.

  TODO: Remove this comment before submitting
-->
### MixHash
MixHash是包含了内容的长度信息的Merkle树的根节点。其构造方法如下：

High |-1-|----63----|----------192----------| Low
1:为0使用SHA256，为1使用Keccak256
63：文件大小
192：根节点Hash的低192位

1. Split the file into 1KB chunks. Pad zeros to the end of the last chunk if needed.

2. Calculate the SHA256 hash for each chunk and the low 128bits is the Merkle tree leaf value

3. Construct a Merkle tree , root node hash algorithm is SHA256, other node use low 128bits of the SHA256

4. Return the combination of the file size at high 64bits and the low 192 bits of the Merkle tree root node hash.

使用MixHash替代被广泛使用的Kaekk256和SHA256，没有任何额外的成本。在高64bits包含了文件的长度虽然在安全性上有一些损失，但192bits的Hash安全性实际上完全足够用了。



### 公有数据的存储证明
0. 能提交存储证明获得奖励的用户被称作Supplier,Supplier需要准备一定的质押币。
1. 区块高度为h的区块Hash得到 32bytes的nonce值和 32-992 的插入位置Pos
2. 为了生成正确的存储证明，Supplier遍历所有的叶子节点，在该位置插入nonce值，选择最合适的叶子节点m。让插入后的根Hash最小
3. Supplier在插入位置之前再计算一个32bytes的noise值，使得新的LeafData可以让默克尔树根Hash符合一个难度条件（比如最低位多少是0）.对于同时进块的存储证明，难度高者胜出并得到奖励。
4. Supplier把存储证明{m,path,leaf_data,noise}提交到链上,即为一个有效的存储证明。可以拿到奖励.不需要PoW的场景可以进一步简化到 {h,m,path_m,m_leaf_data}
5. 链无法验证m是否正确，但其它拥有全量数据的Miner，如果发现m是伪造的，可以提交真实的{new_m,new_path_m,new_m_leaf_data} 来对已上连的存储证明进行挑战并在成功后赢得Supplier的质押币。 
6. 上述设计也可改成Supplier只提交m,挑战者提供path_m, m_leaf_data,但这会导致挑战者需要多1倍的手续费。如果获得的质奖励太少，那么挑战者可能不会提交挑战。

#### 限制
不解决数据是否是公共的问题，也不解决数据是否被访问的问题。该证明的存在只是说明该数据的副本是存在的。
最小文件大小问题：基于上述逻辑不适合保存太小的文件

### 私有数据的存储证明
0. 用户(User)持有待保存的原始私有数据D
1. User决定把数据保存到供应商A，为A准备一个一次性的秘钥K,D通过K加密后得到D'。User将D'保存到A那，然后本地保留基于原始数据构造的挑战本和K
2. User认为供应商A丢失了D'(通常是通过链下判断），基于自己的挑战本在链上提出挑战：（一个32bytes Hash值） 
3. 供应商如果没有丢失数据，可以在Calldata里包含leaf_data （1KB）。挑战结束。供应商获胜。
4. 如果供应商认为Hash并不包含在D'中，提出挑战非法 1byte
5. 用户通过Call Data中的(index 4byte,默克尔路径,1KB )来证明挑战合法，用户获胜。

### IERCPublicDataContract
```
//Review:这个作为ERC的一部分，要仔细考虑一下
interface IERCPublicDataContract {
    //return the owner of the data
    function getDataOwner(bytes32 dataHash) external view returns (address);
}
```

### IERC721VerfiyDataHash
```
interface IERC721VerfiyDataHash{
    //return token data hash
    function tokenDataHash(uint256 _tokenId) external view returns (bytes32);
}
```

#### 限制
存储证明主要用在near-line backup system上。并不适用于在线的数据删除/更新/读取。







## Rationale

<!--
  The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->



## Backwards Compatibility

<!--

  This section is optional.

  All EIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The EIP must explain how the author proposes to deal with these incompatibilities. EIP submissions without a sufficient backwards compatibility treatise may be rejected outright.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->

No backward compatibility issues found.

## Test Cases

<!--
  This section is optional for non-Core EIPs.

  The Test Cases section should include expected input/output pairs, but may include a succinct set of executable tests. It should not include project build files. No new requirements may be be introduced here (meaning an implementation following only the Specification section should pass all tests here.)
  If the test suite is too large to reasonably be included inline, then consider adding it as one or more files in `../assets/eip-####/`. External links will not be allowed

  TODO: Remove this comment before submitting
-->

## Reference Implementation

<!--
  This section is optional.

  The Reference Implementation section should include a minimal implementation that assists in understanding or implementing this specification. It should not include project build files. The reference implementation is not a replacement for the Specification section, and the proposal should still be understandable without it.
  If the reference implementation is too large to reasonably be included inline, then consider adding it as one or more files in `../assets/eip-####/`. External links will not be allowed.

  TODO: Remove this comment before submitting
-->

```solidity
function verifyDataProof(bytes32 meta) {

}


```

## Security Considerations

<!--
  All EIPs must contain a section that discusses the security implications/considerations relevant to the proposed change. Include information that might be important for security discussions, surfaces risks and can be used throughout the life cycle of the proposal. For example, include security-relevant design decisions, concerns, important discussions, implementation-specific guidance and pitfalls, an outline of threats and risks and how they are being addressed. EIP submissions missing the "Security Considerations" section will be rejected. An EIP cannot proceed to status "Final" without a Security Considerations discussion deemed sufficient by the reviewers.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->

隐私安全

数据可靠性

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).