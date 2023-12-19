## The main rules for the NFT inscription game mechanics:

1. The fundamental purpose of the NFT inscription mechanism design is to achieve decentralized storage of NFT data.

2. The Public Data Sponsor (Sponsor) calls the contract interface to create public data. An initial reward is deposited based on the data size. The minimum initial reward is 48 * data size.  

3. Of the rewards deposited into the Public Data, 80% will enter the balance of the public data, and 20% will enter the Award Pool of the system.

4. After public data is created, anyone can make deposits. When a single deposit amount exceeds 110% of the historical maximum single deposit amount of the public data, the Sponsor will be replaced.

5. When creating public data, if an NFT contract address and TokenId are specified, the Owner of the Public Data can be further credibly determined. The rules are as follows:

a) If no contract is specified, the Owner of the data is the first creator. 

b) If a contract is specified but no Index, the Owner is the Author of the contract. 

c) If both contract and Index are specified, the Owner is the Owner of the NFT contract corresponding to the Index.

6. Storage Suppliers can choose to save any Public Data.

7. Storage Suppliers can call the SHOW Data interface, and each successful Show can get a reward. The reward amount is 20% of the Balance of the data displayed.

8. SHOW Data is the core mechanism of the system. A successful Show Data must meet the following conditions: 

a) The Supplier has sufficient qualifications: at the minimum, its remaining space should be 16 times the space of the Public Data.

b) The current block.number meets certain conditions. 

c) Storage challenge parameters are constructed based on the hash of the previous block. The Supplier must submit response data for the storage challenge according to the parameters.

d) The same Supplier can only SHOW one data in a block.

9. After a successful SHOW Data, the Data's Score will increase according to the DataSize.

10. After the end of a Winner cycle, the system will distribute rewards based on the final Score ranking of the top 16 (or 32) Show Data. 

11. The rewards for this cycle's Winners are obtained proportionally by 3 parties: 50% to the Sponsor, 30% to the last 5 successful SHOW Suppliers, and 20% to the Data Owner.


## The games encouraged by the above rules:

1. An obvious winner-takes-all game: Forming an alliance among the Sponsor, Owner, and Supplier to win the competition. This competition strategy will improve the reliability of storing popular NFT data and allow popular NFT Owners to benefit more.

2. Increasing the success rate of SHOW is a key tactical action. Appropriate thresholds will allow the system to have more Suppliers, and these Suppliers will store public data well. 

3. The Sponsor's game: Snatching the Sponsor and Owner of a Public Data about to win is another battlefield. Our designed mechanism will allow popular Public Data to have more Balance, thereby attracting more miners to Show Data.

4. How miners choose which Data to SHOW is a complicated game: Choosing to SHOW popular data may not have a high success rate (everyone Shows in the same block, making endorsements difficult); choosing unpopular data makes it hard to win. But no matter how you choose, having sufficient ammunition is the prerequisite for executing different strategies.

## Some economic logic:
The tokens involved in the above gameplay refer to GWT by default. GWT can be exchanged with the built-in DeFi and currencies we support. The existence of built-in DeFi further diversifies the game rules. 

To be attractive, our gameplay still needs a get-rich myth: The final Award must be attractive. We should support high-value assets. This actually increases the leverage of our capital on hand.


## New ERC: Verified Public Owned Data

From Our rules above:
1. If no contract address is configured, the Owner of the public data cannot be changed.

2. NFT contract address configured but Index not specified:

    - If the contract has DataHash configured, the Owner is the Author and it is trusted data.
    
    - If the NFT contract has Author configured, the Owner is the Author.
    
    - If no Author is configured for the NFT contract, the Owner is all NFT holders. **A dedicated claim contract needs to be developed to simplify reward claims.

3. NFT contract address and Index specified:

    - If the NFT has DataHash configured, it is trusted data.
    
    - The Owner can be determined.

If a (NFT) Contract implement the following interface, it can be considered as a Verified Public Owned Data contract:

```solidity
interface ERCXXXPublicData {
    //return the owner of the data
    function getDataOwner(bytes32 dataHash) public view returns (address);
    //return token data hash
    function tokenData(uint256 _tokenId) external view returns (bytes32);
}
```

### The standard for the bytes32 dataHash: 

The hash value based on the keccak256 algorithm, with the high 64 bits (8 bytes) being the data size, and the low 192 bits (24 bytes) being the low 192 bits of the keccak256 value of the data.

The method to construct the dataHash for a given file:

1. Split the file into 1KB chunks. Pad zeros to the end of the last chunk if needed. 

2. Calculate the keccak256 hash for each chunk.

3. Construct a Merkle tree with the hashes in order.  

4. Return the combination of the file size and the low 192 bits of the keccak256 hash of the Merkle tree root node.
