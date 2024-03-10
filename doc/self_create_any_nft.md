## 自助创建PublicData流程
该流程描述了用户自助创建任何已有的nft的流程。以后该流程可以扩展到任何ERC721的NFT

### 后端的返回信息
未创建桥合约时，后端返回0地址即可

### 前端创建桥合约
当前端发现后端返回的桥合约为0地址时：
1. 创建桥合约
   调用钱包创建一个ERC721NFTSelfBridge合约。rust里可以直接通过bytecode创建一个合约，js里应该也有对应的操作。
   构造参数为
   > constructor(IERC721 _nftAddress, address _admin, bytes32[] memory dataMixedHash, uint256[] memory tokenId)

  这些参数都由后端返回。产品上的dataMixedHash和tokenId应该是只有一个的，这里保留了以后批量设置的能力

2. 前端等待合约创建完成。创建完成后，应取到创建的桥合约地址，然后调用后端的接口，上报桥合约地址
3. 后端收到桥合约地址后，检查合约数据是否正确。然后用admin身份调用PublicDataStorage合约的allowPublicDataContract接口，让这个桥合约地址生效

### 前端发现已有桥合约
1. 调用桥合约的接口`getTokenId(bytes32 dataMixedHash) public view returns (uint256, bool)`，做数据检测。
2. 如果bool返回false，说明该数据没有上桥。调用`setTokenId(bytes32[] calldata dataMixedHash, uint256[] calldata tokenId)`接口上桥后再create即可
3. 如果bool返回true，但uint256表示的tokenid与后台的不符，说明链上数据有误，这里调后台一个接口上报一下，并阻止任何链上操作
4. 如果bool返回true，且uint256表示的tokenid与后台的相同，说明链上数据正确，走现在的流程就行。

前端已有桥合约的检测操作，须在所有链上操作前都进行。包括create，赞助，show。tokenid与后台不符时不允许操作。并需要上报