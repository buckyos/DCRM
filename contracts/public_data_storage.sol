// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./gwt.sol";

interface IERCPublicDataContract {
    // return contract`s owner
    function owner() external view returns (address);
    //return the owner of the data
    function getDataOwner(bytes32 dataHash) external view returns (address);

    //return token data hash
    function tokenDataHash(uint256 _tokenId) external view returns (bytes32);
}

contract PublicDataStorage {
    struct PublicData {
        bytes32 mixedHash;
        address owner;
        address sponsor;
        address nftContract;
        uint256 tokenId;
        uint256 maxDeposit;
        uint256 totalScore;
    }

    GWTToken public gwtToken;// Gb per Week Token

    mapping(bytes32 => PublicData) public_datas;
    uint256 system_reward_pool;
    mapping(bytes32 => uint256) data_balance;
    mapping(uint256 => mapping(address => bool)) all_shows;

    struct CycleInfo {
        uint256 score;
        address[] last_showers;
        uint8 shower_index;
    }

    mapping(uint256 => mapping(bytes32 => CycleInfo)) cycle_infos;

    uint256 startBlock;

    constructor(address _gwtToken) {
        gwtToken = GWTToken(_gwtToken);
        startBlock = block.number;
    }

    function getDataSize(bytes32 dataHash) public pure returns (uint64) {
        return uint64(uint256(dataHash) >> 192);
    }

    function _verifyData(
        address sender,
        bytes32 dataMixedHash,
        bytes32 blockHash,
        bytes32 showHash
    ) internal returns(bool) {
        return showHash == keccak256(abi.encodePacked(sender, dataMixedHash, blockHash, block.number));
    }

    function _verifyBlockNumber(bytes32 dataMixedHash, uint256 blockNumber) internal returns(bool) {
        // (blockNumber xor dataMixedHash) % 64 == 0
        return uint256(bytes32(blockNumber) ^ dataMixedHash) % 64 == 0;
    }

    function _cycleNumber() internal view returns(uint256) {
        uint cycleNumber = (block.number - startBlock) / 17280;
        if (cycleNumber * 17280 + startBlock < block.number) {
            cycleNumber += 1;
        }
        return cycleNumber;
    }

    function createPublicData(
        bytes32 dataMixedHash,
        uint64 depositRatio,
        address publicDataContract,
        uint256 tokenId
    ) public {
        PublicData storage publicDataInfo = public_datas[dataMixedHash];
        publicDataInfo.mixedHash = dataMixedHash;
        if (publicDataContract == address(0)) {
            publicDataInfo.owner = msg.sender;
        } else if (tokenId == 0) {
            // token id must be greater than 0
            publicDataInfo.owner = IERCPublicDataContract(publicDataContract).owner();
        } else {
            require(dataMixedHash == IERCPublicDataContract(publicDataContract).tokenDataHash(tokenId));
            publicDataInfo.nftContract = publicDataContract;
            publicDataInfo.tokenId = tokenId;
        }

        // transfer deposit
        require(depositRatio >= 48);

        // get data size from data hash
        uint64 dataSize = getDataSize(publicDataInfo.mixedHash);
        uint256 depositAmount = (depositRatio * dataSize * 10 ** 18) >> 30;

        publicDataInfo.maxDeposit = depositAmount;

        gwtToken.transferFrom(msg.sender, address(this), depositAmount);
        data_balance[publicDataInfo.mixedHash] += (depositAmount * 8) / 10;
        system_reward_pool += depositAmount - ((depositAmount * 8) / 10);

        public_datas[dataMixedHash] = publicDataInfo;
    }

    function addDeposit(bytes32 dataMixedHash, uint256 depositAmount) public {
        PublicData storage publicDataInfo = public_datas[dataMixedHash];
        require(publicDataInfo.mixedHash != bytes32(0));
        require(publicDataInfo.owner == msg.sender);

        // transfer deposit
        gwtToken.transferFrom(msg.sender, address(this), depositAmount);
        data_balance[publicDataInfo.mixedHash] += (depositAmount * 8) / 10;
        system_reward_pool += depositAmount - ((depositAmount * 8) / 10);

        if (depositAmount > ((publicDataInfo.maxDeposit * 11) / 10)) {
            publicDataInfo.sponsor = msg.sender;
        }

        if (depositAmount > publicDataInfo.maxDeposit) {
            publicDataInfo.maxDeposit = depositAmount;
        }
    }


    function _validPublicSupplier(address supplierAddress, bytes32 dataMixedHash) internal view returns(bool) {
        // TODO: How to ensure the supplier has centern remaining space? GWT Token balance?
        return gwtToken.balanceOf(supplierAddress) > 16 * 10 ** 18 * (getDataSize(dataMixedHash) >> 30);
    }

    // msg.sender is supplier
    // show_hash = keccak256(abiEncode[sender, dataMixedHash, prev_block_hash, block_number])
    function showData(bytes32 dataMixedHash, bytes32 showHash) public {
        address supplier = msg.sender;
        require(_validPublicSupplier(supplier, dataMixedHash));
        // 每个块的每个supplier只能show一次数据
        require(all_shows[block.number][supplier] == false);      

        // check block.number meets certain conditions
        require(_verifyBlockNumber(dataMixedHash, block.number));

        // check showHash is correct
        require(_verifyData(supplier, dataMixedHash, blockhash(block.number - 1), showHash));

        PublicData storage publicDataInfo = public_datas[dataMixedHash];

        // There may be some predicated logic here that is beneficial to optimize the sorting

        CycleInfo storage cycleInfo = cycle_infos[_cycleNumber()][dataMixedHash];
        cycleInfo.score += getDataSize(publicDataInfo.mixedHash) >> 30;

        // insert supplier into last_showers
        if (cycleInfo.shower_index >= 5) {
            cycleInfo.shower_index = 0;
        }
        cycleInfo.last_showers[cycleInfo.shower_index] = supplier;
        cycleInfo.shower_index += 1;

        // 给成功的show一些奖励
        uint256 reward = data_balance[publicDataInfo.mixedHash] * 2 / 10;
        if (reward > 0) {
            gwtToken.transfer(supplier, reward);
            data_balance[publicDataInfo.mixedHash] -= reward;
        }
        
        all_shows[block.number][supplier] = true;
    }

    function withdraw(uint cycleNumber, bytes32 dataMixedHash) public {
        CycleInfo storage cycleInfo = cycle_infos[cycleNumber][dataMixedHash];
        require(cycleInfo.score > 0);
        // TODO
    }
}
