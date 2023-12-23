// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./gwt.sol";
import "./sortedlist.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

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

    struct SupplierInfo {
        mapping(bytes32 => uint256) pledge;
        uint256 lastShowBlock;
    }

    GWTToken public gwtToken;// Gb per Week Token

    mapping(address => SupplierInfo) supplier_pledge;

    mapping(bytes32 => PublicData) public_datas;
    uint256 system_reward_pool;
    mapping(bytes32 => uint256) data_balance;
    // 这里相当于记得是supplier的show记录，共挑战用
    struct ShowData {
        uint256 nonce_block;
        uint256 show_block;
        uint256 rewardAmount;
        bytes32 minHash;
    }
    mapping(address => mapping(bytes32 => ShowData)) show_datas;
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
    uint256 constant public topRewards = 32;
    uint256 constant public lockAfterShow = 240;    // 成功的SHOW一小时内不允许提现
    uint256 constant public maxNonceBlockDistance = 2;  // 允许的nonce block距离, lockAfterShow + maxNonceBlockDistance要小于256
    uint256 constant public difficulty = 4;   // POW难度，最后N个bit为0
    uint256 constant public showDepositRatio = 3; // SHOW的时候抵押的GWT倍数
    uint256 constant public totalRewardScore = 1572; // 将rewardScores相加得到的结果

    event GWTStacked(address supplier, bytes32 mixedHash, uint256 amount);
    event GWTUnstacked(address supplier, bytes32 mixedHash, uint256 amount);
    event PublicDataCreated(bytes32 mixedHash);
    event SponserChanged(bytes32 mixedHash, address oldSponser, address newSponser);
    event DataShowed(bytes32 mixedHash, address shower, uint256 score);
    event Withdraw(bytes32 mixedHash, address user, uint256 amount);
    event ChallengeSuccess(address challenger, address challenged, uint256 show_block_number, bytes32 mixedHash, uint256 amount);

    constructor(address _gwtToken) {
        gwtToken = GWTToken(_gwtToken);
        startBlock = block.number;
    }

    function _getRewardScore(uint256 ranking) internal pure returns(uint256) {
        uint8[32] memory rewardScores = [
            240, 180, 150, 120, 100, 80, 60, 50, 40, 
            35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 
            24, 23, 22, 21, 20, 19, 18 ,17, 16, 15, 14, 13
        ];

        if (ranking <= rewardScores.length) {
            return rewardScores[ranking - 1];
        } else {
            return 0;
        }
    }

    function getDataSize(bytes32 dataHash) public pure returns (uint64) {
        return uint64(uint256(dataHash) >> 192);
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

    function dataBalance(bytes32 dataMixedHash) public view returns(uint256) {
        return data_balance[dataMixedHash];
    }

    function pledgeGWT(uint256 amount, bytes32 dataMixedHash) public {
        gwtToken.transferFrom(msg.sender, address(this), amount);
        supplier_pledge[msg.sender].pledge[dataMixedHash] += amount;

        emit GWTStacked(msg.sender, dataMixedHash, amount);
    }

    function unstakeGWT(uint256 amount, bytes32 dataMixedHash) public {
        // 如果没SHOW过的话，lastShowBlock为0，可以提取
        require(block.number > supplier_pledge[msg.sender].lastShowBlock + lockAfterShow);
        require(supplier_pledge[msg.sender].pledge[dataMixedHash] >= amount);
        gwtToken.transfer(msg.sender, amount);
        supplier_pledge[msg.sender].pledge[dataMixedHash] -= amount;

        emit GWTUnstacked(msg.sender, dataMixedHash, amount);
    }

    function _validPublicSupplier(address supplierAddress, bytes32 dataMixedHash) internal returns(bool) {
        uint256 supplierPledge = supplier_pledge[supplierAddress].pledge[dataMixedHash];
        uint256 showReward = data_balance[public_datas[dataMixedHash].mixedHash] / 10;
        return supplierPledge > showDepositRatio * showReward;
    }

    function _verifyData(
        bytes32 nonce,
        uint256 pos,
        uint32 index,
        bytes32[] calldata m_path,
        bytes calldata leafdata,
        bytes32 noise
    ) internal returns(bool) {
        // TODO：如何通过index和m_path检验这个index是否正确？

        bytes32 leaf_hash = keccak256(abi.encodePacked(leafdata[:pos], nonce, noise, leafdata[pos:]));
        bytes32 merkleHash = MerkleProof.processProofCalldata(m_path, leaf_hash);
        
        // 判断hash的最后N位是否为0
        return uint256(merkleHash) & 1 << difficulty - 1 == 0;
    }

    // msg.sender is supplier
    // show_hash = keccak256(abiEncode[sender, dataMixedHash, prev_block_hash, block_number])
    function showData(bytes32 dataMixedHash, uint256 nonce_block, uint32 index, bytes32[] calldata m_path, bytes calldata leafdata, bytes32 noise) public {
        address supplier = msg.sender;
        require(nonce_block < block.number && block.number - nonce_block < maxNonceBlockDistance);
        require(_validPublicSupplier(supplier, dataMixedHash));
        // 每个块的每个supplier只能show一次数据
        require(all_shows[block.number][supplier] == false);

        // check block.number meets certain conditions
        require(_verifyBlockNumber(dataMixedHash, block.number));

        bytes32 nonce = blockhash(nonce_block);
        uint256 pos = uint256(nonce) % 960 + 32;    // 产生的pos在[32, 992]

        // check showHash is correct
        require(_verifyData(nonce, pos, index, m_path, leafdata, noise));

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
            supplier_pledge[supplier].lastShowBlock = block.number;
        }

        // 记录minhash供挑战
        bytes32 minMerkleHash = MerkleProof.processProofCalldata(m_path, keccak256(abi.encodePacked(leafdata[:pos], nonce, leafdata[pos:])));
        show_datas[supplier][dataMixedHash] = ShowData(nonce_block, block.number, reward, minMerkleHash);

        // 更新这次cycle的score排名
        if (cycleInfo.score_list.maxlen() < topRewards) {
            cycleInfo.score_list.setMaxLen(topRewards);
        }
        cycleInfo.score_list.updateScore(dataMixedHash, dataInfo.score);
        
        all_shows[block.number][supplier] = true;

        emit DataShowed(dataMixedHash, supplier, dataInfo.score);
    }

    // 挑战challengeTo在show_block_number上对dataMixedHash的show
    function challenge(address challengeTo, bytes32 dataMixedHash, uint256 show_block_number, uint32 index, bytes32[] calldata m_path, bytes calldata leafdata) public {
        require(show_block_number == show_datas[challengeTo][dataMixedHash].show_block);
        require(block.number < show_block_number + lockAfterShow);

        //TODO: 如何验证index是正确的？
        bytes32 nonce = blockhash(show_datas[challengeTo][dataMixedHash].nonce_block);
        uint256 pos = uint256(nonce) % 960 + 32;    // 产生的pos在[32, 992]

        bytes32 minMerkleHash = MerkleProof.processProofCalldata(m_path, keccak256(abi.encodePacked(leafdata[:pos], nonce, leafdata[pos:])));
        if (uint256(minMerkleHash) < uint256(show_datas[challengeTo][dataMixedHash].minHash)) {
            // 扣除奖励的showDepositRatio倍
            uint256 reward = show_datas[challengeTo][dataMixedHash].rewardAmount * showDepositRatio;
            supplier_pledge[challengeTo].pledge[dataMixedHash] -= reward;
            gwtToken.transfer(msg.sender, reward);
            emit ChallengeSuccess(msg.sender, challengeTo, show_block_number, dataMixedHash, reward);
        }
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
        uint8 user = 0;
        if (sender == publicDataInfo.sponsor) {
            user |= 1 << 1;
        }

        if (sender == _getDataOwner(dataMixedHash)) {
            user |= 1 << 7;
        } 
    
        CycleDataInfo memory dataInfo = cycle_infos[_cycleNumber()].data_infos[dataMixedHash];
        for (uint8 i = 0; i < dataInfo.last_showers.length; i++) {
            if (dataInfo.last_showers[i] == sender) {
                user |= uint8(1 << (i+2));
            }
        }

        return user;
    }

    // sponser拿50%, owner拿20%, 5个last shower平分30%
    function _calcuteReward(uint8 user, uint256 totalReward, uint256 last_shower_length) internal pure returns(uint256) {
        uint reward = 0;
        if ((user >> 7) & 1 == 1) {
            reward += totalReward / 2;
        } 
        if ((user >> 1) & 1 == 1) {
            reward += totalReward / 5;
        }
        if (user & 124 > 0) {
            reward += (totalReward - totalReward / 2 - totalReward / 5) / last_shower_length;
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
        require(dataInfo.withdraw_status & withdrawUser == 0);

        // 计算该得到多少奖励
        uint256 totalReward = cycleInfo.total_award * 8 / 10;

        uint256 dataReward = totalReward * _getRewardScore(scoreListRanking) / totalRewardScore;

        uint256 reward = _calcuteReward(withdrawUser, dataReward, dataInfo.last_showers.length);
        gwtToken.transfer(msg.sender, reward);
        
        // 设置已取标志
        dataInfo.withdraw_status |= withdrawUser;


        emit Withdraw(dataMixedHash, msg.sender, reward);
    }
}
