// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./gwt.sol";
import "./sortedlist.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

using SortedScoreList for SortedScoreList.List;

interface IERCPublicDataContract {
    //return the owner of the data
    function getDataOwner(bytes32 dataHash) external view returns (address);

    //return token data hash
    function tokenDataHash(uint256 _tokenId) external view returns (bytes32);
}

/**
 * 有关奖励逻辑：
 * 每个周期的奖励 = 上个周期的奖励 * 0.2 + 这个周期的所有赞助 * 0.2
 * 因此，在每次收入奖励时，更新本周期的奖励额度
 * 当本周期奖励额度为0时，以上个周期的奖励*0.2起始
 * 可能有精度损失？
 */

/**
 * 积分规则是什么样的？我先定一个，取top N，第一名积分N，第二名N-1，一直到1为止
 */

contract PublicDataStorage {
    struct PublicData {
        bytes32 mixedHash;
        address owner;
        address sponsor;
        address nftContract;
        uint256 tokenId;
        uint256 maxDeposit;
    }

    GWTToken public gwtToken;// Gb per Week Token

    mapping(address => uint256) supplier_pledge;
    mapping(bytes32 => mapping(address => bool)) data_suppliers;

    mapping(bytes32 => PublicData) public_datas;
    uint256 system_reward_pool;
    mapping(bytes32 => uint256) data_balance;
    mapping(uint256 => mapping(address => bool)) all_shows;

    struct CycleDataInfo {
        uint256 score;
        address[] last_showers;
        uint8 shower_index;
        uint8 withdraw_status;
    }

    struct CycleInfo {
        mapping(bytes32 => CycleDataInfo) data_infos; 
        SortedScoreList.List score_list;
        uint256 total_award;    // 记录这个cycle的总奖励
    }

    mapping(uint256 => CycleInfo) cycle_infos;

    uint256 startBlock;

    // 合约常量参数
    uint256 constant public blocksPerCycle = 17280;
    uint256 constant public topRewards = 16;

    event GWTStacked(address supplier, uint256 amount);
    event GWTUnstacked(address supplier, uint256 amount);
    event MarkData(address supplier, bytes32 mixedHash, uint256 lockedAmount);
    event UnmarkData(address supplier, bytes32 mixedHash, uint256 lockedAmount);
    event PublicDataCreated(bytes32 mixedHash);
    event SponserChanged(bytes32 mixedHash, address oldSponser, address newSponser);
    event DataShowed(bytes32 mixedHash, address shower, uint256 score);
    event Withdraw(bytes32 mixedHash, address user, uint256 amount);

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
    ) internal view returns(bool) {
        return showHash == keccak256(abi.encodePacked(sender, dataMixedHash, blockHash, block.number));
    }

    function _verifyBlockNumber(bytes32 dataMixedHash, uint256 blockNumber) internal pure returns(bool) {
        // (blockNumber xor dataMixedHash) % 64 == 0
        return uint256(bytes32(blockNumber) ^ dataMixedHash) % 64 == 0;
    }

    function _cycleNumber() internal view returns(uint256) {
        uint cycleNumber = (block.number - startBlock) / blocksPerCycle;
        if (cycleNumber * blocksPerCycle + startBlock < block.number) {
            cycleNumber += 1;
        }
        return cycleNumber;
    }

    function _addCycleReward(uint256 amount) private {
        uint256 cycleNumber = _cycleNumber();
        CycleInfo storage cycleInfo = cycle_infos[cycleNumber];
        if (cycleInfo.total_award == 0) {
            uint256 lastCycleReward = cycle_infos[cycleNumber - 1].total_award;
            cycleInfo.total_award += lastCycleReward - (lastCycleReward * 4 / 5);
        }
        cycleInfo.total_award += amount;
    }

    // 计算这些空间对应多少GWT，单位是wei
    function _dataSizeToGWT(uint64 dataSize) internal pure returns(uint256) {
        return (dataSize * 10 ** 18) >> 30;
    }

    function createPublicData(
        bytes32 dataMixedHash,
        uint64 depositRatio,
        address publicDataContract,
        uint256 tokenId
    ) public {
        PublicData storage publicDataInfo = public_datas[dataMixedHash];
        require(publicDataInfo.mixedHash == bytes32(0));

        publicDataInfo.mixedHash = dataMixedHash;
        publicDataInfo.sponsor = msg.sender;

        if (publicDataContract == address(0)) {
            publicDataInfo.owner = msg.sender;
        } else if (tokenId == 0) {
            // token id must be greater than 0
            // 当合约不是IERCPublicDataContract时，是否可以将owner设置为contract地址？
            // 是不是可以认为这是个Ownerable合约？
            publicDataInfo.owner = Ownable(publicDataContract).owner();
        } else {
            require(dataMixedHash == IERCPublicDataContract(publicDataContract).tokenDataHash(tokenId));
            publicDataInfo.nftContract = publicDataContract;
            publicDataInfo.tokenId = tokenId;
        }

        // transfer deposit
        require(depositRatio >= 48);

        // get data size from data hash
        uint64 dataSize = getDataSize(publicDataInfo.mixedHash);
        uint256 depositAmount = depositRatio * _dataSizeToGWT(dataSize);

        publicDataInfo.maxDeposit = depositAmount;

        gwtToken.transferFrom(msg.sender, address(this), depositAmount);
        data_balance[publicDataInfo.mixedHash] += (depositAmount * 8) / 10;
        uint256 system_reward = depositAmount - ((depositAmount * 8) / 10);
        system_reward_pool += system_reward;
        _addCycleReward(system_reward);

        public_datas[dataMixedHash] = publicDataInfo;

        emit PublicDataCreated(dataMixedHash);
        emit SponserChanged(dataMixedHash, address(0), msg.sender);
    }

    function getOwner(bytes32 dataMixedHash) public view returns(address) {
        PublicData memory info = public_datas[dataMixedHash];
        if (info.owner != address(0)) {
            return info.owner;
        } else {
            return IERCPublicDataContract(info.nftContract).getDataOwner(dataMixedHash);
        }
    }

    function addDeposit(bytes32 dataMixedHash, uint256 depositAmount) public {
        PublicData storage publicDataInfo = public_datas[dataMixedHash];
        require(publicDataInfo.mixedHash != bytes32(0));
        require(publicDataInfo.owner == msg.sender);

        // transfer deposit
        gwtToken.transferFrom(msg.sender, address(this), depositAmount);
        data_balance[publicDataInfo.mixedHash] += (depositAmount * 8) / 10;

        uint256 system_reward = depositAmount - ((depositAmount * 8) / 10);
        system_reward_pool += system_reward;
        _addCycleReward(system_reward);

        if (depositAmount > publicDataInfo.maxDeposit) {
            publicDataInfo.maxDeposit = depositAmount;
        }

        if (depositAmount > ((publicDataInfo.maxDeposit * 11) / 10)) {
            address oldSponser = publicDataInfo.sponsor;
            publicDataInfo.sponsor = msg.sender;
            emit SponserChanged(dataMixedHash, oldSponser, msg.sender);
        }
    }

    function pledgeGWT(uint256 amount) public {
        gwtToken.transferFrom(msg.sender, address(this), amount);
        supplier_pledge[msg.sender] += amount;

        emit GWTStacked(msg.sender, amount);
    }

    function unstakeGWT(uint256 amount) public {
        require(supplier_pledge[msg.sender] >= amount);
        gwtToken.transfer(msg.sender, amount);
        supplier_pledge[msg.sender] -= amount;

        emit GWTUnstacked(msg.sender, amount);
    }


    // supplier表示自己将要show对应的数据
    function markData(bytes32 mixedHash) public {
        address supplier = msg.sender;
        PublicData memory publicDataInfo = public_datas[mixedHash];
        require(publicDataInfo.mixedHash != bytes32(0));
        require(data_suppliers[mixedHash][supplier] == false);

        uint256 lockedAmount = _dataSizeToGWT(getDataSize(mixedHash));
        require(supplier_pledge[supplier] >= lockedAmount);

        // lock gwt
        supplier_pledge[supplier] -= lockedAmount;
        data_suppliers[mixedHash][supplier] = true;
    }

    function unmarkData(bytes32 mixedHash) public {
        address supplier = msg.sender;
        PublicData memory publicDataInfo = public_datas[mixedHash];
        require(publicDataInfo.mixedHash != bytes32(0));
        require(data_suppliers[mixedHash][supplier] == true);

        uint256 lockedAmount = _dataSizeToGWT(getDataSize(mixedHash));
        supplier_pledge[supplier] += lockedAmount;
        data_suppliers[mixedHash][supplier] = false;
    }


    function _validPublicSupplier(address supplierAddress, bytes32 dataMixedHash) internal returns(bool) {
        uint256 supplierPledge = supplier_pledge[supplierAddress];
        uint64 dataSize = getDataSize(dataMixedHash);
        return supplierPledge > 16 * _dataSizeToGWT(dataSize);
    }

    // msg.sender is supplier
    // show_hash = keccak256(abiEncode[sender, dataMixedHash, prev_block_hash, block_number])
    function showData(bytes32 dataMixedHash, bytes32 showHash) public {
        address supplier = msg.sender;
        require(data_suppliers[dataMixedHash][supplier] == true);
        require(_validPublicSupplier(supplier, dataMixedHash));
        // 每个块的每个supplier只能show一次数据
        require(all_shows[block.number][supplier] == false);      

        // check block.number meets certain conditions
        require(_verifyBlockNumber(dataMixedHash, block.number));

        // check showHash is correct
        require(_verifyData(supplier, dataMixedHash, blockhash(block.number - 1), showHash));

        PublicData storage publicDataInfo = public_datas[dataMixedHash];

        CycleInfo storage cycleInfo = cycle_infos[_cycleNumber()];
        CycleDataInfo storage dataInfo = cycleInfo.data_infos[dataMixedHash];
        dataInfo.score += getDataSize(publicDataInfo.mixedHash);

        // insert supplier into last_showers
        if (dataInfo.shower_index >= 5) {
            dataInfo.shower_index = 0;
        }
        dataInfo.last_showers[dataInfo.shower_index] = supplier;
        dataInfo.shower_index += 1;

        // 给成功的show一些奖励
        uint256 reward = data_balance[publicDataInfo.mixedHash] / 10;
        if (reward > 0) {
            gwtToken.transfer(supplier, reward);
            data_balance[publicDataInfo.mixedHash] -= reward;
        }

        // 更新这次cycle的score排名
        if (cycleInfo.score_list.maxlen() < topRewards) {
            cycleInfo.score_list.setMaxLen(topRewards);
        }
        cycleInfo.score_list.updateScore(dataMixedHash, dataInfo.score);
        
        all_shows[block.number][supplier] = true;

        emit DataShowed(dataMixedHash, supplier, dataInfo.score);
    }

    function _getDataOwner(bytes32 dataMixedHash) internal view returns(address) {
        PublicData memory publicDataInfo = public_datas[dataMixedHash];
        if (publicDataInfo.owner != address(0)) {
            return publicDataInfo.owner;
        } else {
            return IERCPublicDataContract(publicDataInfo.nftContract).getDataOwner(dataMixedHash);
        }
    }

    // return: 1: sponser, 2- 6: last shower, 7: owner, 0: no one
    function _getWithdrawUser(bytes32 dataMixedHash) internal view returns(uint8) {
        address sender = msg.sender;
        PublicData memory publicDataInfo = public_datas[dataMixedHash];
        if (sender == publicDataInfo.sponsor) {
            return 1;
        } else if (sender == _getDataOwner(dataMixedHash)) {
            return 7;
        } else {
            CycleDataInfo memory dataInfo = cycle_infos[_cycleNumber()].data_infos[dataMixedHash];
            for (uint i = 0; i < dataInfo.last_showers.length; i++) {
                if (dataInfo.last_showers[i] == sender) {
                    return uint8(i + 2);
                }
            }
            return 0;
        }
    }

    // sponser拿50%, owner拿20%, 5个last shower平分30%
    function _calcuteReward(uint8 user, uint256 totalReward) internal pure returns(uint256) {
        if (user == 1) {
            return totalReward / 2;
        } else if (user == 7) {
            return totalReward / 5;
        } else {
            return totalReward - (totalReward * 7 / 10) / 5;
        }
    }

    function withdraw(uint cycleNumber, bytes32 dataMixedHash) public {
        // 判断这次的cycle已经结束
        require(block.number > cycleNumber * blocksPerCycle + startBlock);
        CycleInfo storage cycleInfo = cycle_infos[_cycleNumber()];
        CycleDataInfo storage dataInfo = cycleInfo.data_infos[dataMixedHash];
        uint256 scoreListRanking = cycleInfo.score_list.getRanking(dataMixedHash);
        require(scoreListRanking > 0);

        // 看看是谁来取
        uint8 withdrawUser = _getWithdrawUser(dataMixedHash);

        require(withdrawUser > 0);
        require(dataInfo.withdraw_status & uint8(1 << withdrawUser) == 0);

        // 计算该得到多少奖励
        uint256 totalReward = cycleInfo.total_award * 8 / 10;
        // 积分规则我先自己定一个, 参见最顶上的注释
        uint256 totalScore = (1 + topRewards) * topRewards / 2;
        uint256 ranking = topRewards - scoreListRanking + 1;
        uint256 dataReward = totalReward * ranking / totalScore;

        uint256 reward = _calcuteReward(withdrawUser, dataReward);
        gwtToken.transfer(msg.sender, reward);
        
        // 设置已取标志
        dataInfo.withdraw_status |= uint8(1 << withdrawUser);


        emit Withdraw(dataMixedHash, msg.sender, reward);
    }
}
