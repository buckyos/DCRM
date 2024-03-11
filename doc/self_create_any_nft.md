## 自助创建PublicData流程
该流程描述了用户自助创建任何已有的nft的流程。以后该流程可以扩展到任何ERC721的NFT

### 前置操作
我们自己上一个统一的ERC721NFTSelfBridge合约
后端将所有未上链的mixhash的bridge都设置成这个合约的地址

### 前端的检测逻辑
当桥合约的地址是统一桥合约时，需做以下的检测逻辑。其他桥合约地址不需要：
1. 调用桥合约的接口`getTokenId(bytes32 dataMixedHash) public view returns (NFTInfo memory)`，做数据检测。
   ```solidity
    struct NFTInfo {
            uint256 tokenId;
            address nftAddress;
            bool inited;
        }
   ```
2. 如果inited为false，说明该数据没有上桥。调用`setTokenId(bytes32[] calldata dataMixedHash, address[] calldata nftAddress, uint256[] calldata tokenId)`接口上桥后再create即可
3. 如果inited为true，但tokenId和nftAddress与后台的不符，说明链上数据有误，这里调后台一个接口上报一下，并阻止任何链上操作
4. 如果inited为true，且tokenId和nftAddress与后台的相同，说明链上数据正确，走现在的流程就行。

前端已有桥合约的检测操作，须在所有链上操作前都进行。包括create，赞助，show。tokenid与后台不符时不允许操作。并需要上报