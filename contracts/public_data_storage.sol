// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./gwt.sol";
import "./sortedlist.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

using SortedScoreList for SortedScoreList.List;

//Review:这个作为ERC的一部分，要仔细考虑一下
interface IERCPublicDataContract {
    //return the owner of the data
    function getDataOwner(bytes32 dataHash) external view returns (address);
}

interface IERC721VerfiyDataHash{
    //return token data hash
    function tokenDataHash(uint256 _tokenId) external view returns (bytes32);
}
// Review: 考虑有一些链的出块时间不确定,使用区块间隔要谨慎，可以用区块的时间戳


// mixedDataHash: 2bit hash algorithm + 62bit data size + 192bit data hash
// 2bit hash algorithm: 00: keccak256, 01: sha256

/**
 * 有关奖励逻辑：
 * 每个周期的奖励 = 上个周期的奖励 * 0.2 + 这个周期的所有赞助 * 0.2
 * 因此，在每次收入奖励时，更新本周期的奖励额度
 * 当本周期奖励额度为0时，以上个周期的奖励*0.2起始
 * 可能有精度损失？
 */

contract PublicDataStorage {
    struct PublicData {
        address owner;
        address sponsor;
        address nftContract;
        uint256 tokenId;
        uint256 maxDeposit;
        uint256 data_balance;
    }

    struct SupplierInfo {
        mapping(bytes32 => uint256) pledge;
        uint256 lastShowBlock;
    }

    GWTToken public gwtToken;// Gb per Week Token

    mapping(address => SupplierInfo) supplier_pledge;

    mapping(bytes32 => PublicData) public_datas;
    
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
    // REVIEW by weiqiushi: 我们其实不需要记录系统的总奖励，每个周期有记录就可以了，提现的时候也是靠cycle reward来计算的
    //uint256 sysBalance = 0;
    uint256 currectCycle;

    // 合约常量参数
    uint256 sysMinDepositRatio = 64;
    uint256 sysMinPublicDataStorageWeeks = 96;
    uint256 constant public blocksPerCycle = 17280;
    uint256 constant public topRewards = 32;
    uint256 constant public lockAfterShow = 240;    // 成功的SHOW一小时内不允许提现
    uint256 constant public maxNonceBlockDistance = 2;  // 允许的nonce block距离, lockAfterShow + maxNonceBlockDistance要小于256
    uint256 constant public difficulty = 4;   // POW难度，最后N个bit为0
    uint256 constant public showDepositRatio = 3; // SHOW的时候抵押的GWT倍数
    uint256 constant public totalRewardScore = 1572; // 将rewardScores相加得到的结果
    uint64 constant public sysMinDataSize = 1 << 27; // dataSize换算GWT时，最小值为100M

    event GWTStacked(address supplier, bytes32 mixedHash, uint256 amount);
    event GWTUnstacked(address supplier, bytes32 mixedHash, uint256 amount);
    event PublicDataCreated(bytes32 mixedHash);
    event DepositData(address depositer, bytes32 mixedHash, uint256 balance, uint256 reward);
    event SponserChanged(bytes32 mixedHash, address oldSponser, address newSponser);
    event DataShowed(bytes32 mixedHash, address shower, uint256 score);
    event WithdrawAward(bytes32 mixedHash, address user, uint256 amount);
    event ChallengeSuccess(address challenger, address challenged, uint256 show_block_number, bytes32 mixedHash, uint256 amount);

    constructor(address _gwtToken) {
        gwtToken = GWTToken(_gwtToken);
        startBlock = block.number;
        currectCycle = 0;
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
        return uint64(uint256(dataHash) >> 192) | uint64((1 << 62) - 1);
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

    // 通过记录一个最后的周期来解决周期之间可能有空洞的问题
    function _addCycleReward(uint256 amount) private {
        uint256 cycleNumber = _cycleNumber();
        CycleInfo storage cycleInfo = cycle_infos[cycleNumber];
        if (cycleInfo.total_award == 0) {
            uint256 lastCycleReward = cycle_infos[currectCycle].total_award;
            cycleInfo.total_award = (lastCycleReward * 3 / 20);
            // REVIEW by weiqiushi: 这里只是记录cycle之间的奖励转移，系统奖池里的资金没有真正的变化
            // sysBalance += (lastCycleReward / 20);
            cycle_infos[cycleNumber - 1].total_award = lastCycleReward * 4 / 5;
        }
        cycleInfo.total_award += amount;

        if (currectCycle != cycleNumber) {
            // 进入了一个新的周期
            currectCycle = cycleNumber;
        }
        
    }

    // 计算这些空间对应多少GWT，单位是wei
    // 不满128MB的按照128MB计算
    function _dataSizeToGWT(uint64 dataSize) internal pure returns(uint256) {
        uint64 fixedDataSize = dataSize;
        if (fixedDataSize < sysMinDataSize) {
            fixedDataSize = sysMinDataSize;
        }
        return (fixedDataSize * 10 ** 18) >> 30;
    }

    function createPublicData(
        bytes32 dataMixedHash,
        uint64 depositRatio,
        uint256 depositAmount, //希望打入的GWT余额
        address publicDataContract,//REVIEW:现在的实现简单，但应考虑更简单的导入整个NFT合约的所有Token的情况
        uint256 tokenId
    ) public {
        require(depositRatio >= sysMinDepositRatio, "deposit ratio is too small");
        require(dataMixedHash != bytes32(0), "data hash is empty");

        PublicData storage publicDataInfo = public_datas[dataMixedHash];
        require(publicDataInfo.maxDeposit == 0);

        // get data size from data hash
        uint64 dataSize = getDataSize(dataMixedHash);
        // 区分质押率和最小时长。最小时长是系统参数，质押率depositRatio是用户参数
        // 质押率影响用户SHOW数据所需要冻结的质押
        // minAmount = 数据大小*最小时长*质押率，
        uint256 minAmount = depositRatio * _dataSizeToGWT(dataSize) * sysMinPublicDataStorageWeeks;
        require(depositAmount >= minAmount, "deposit amount is too small");
        publicDataInfo.maxDeposit = depositAmount;
        publicDataInfo.sponsor = msg.sender;
        gwtToken.transferFrom(msg.sender, address(this), depositAmount);

        if (publicDataContract == address(0)) {
            publicDataInfo.owner = msg.sender;
        } else if (tokenId == 0) {
            // token id must be greater than 0
            // TODO: 这里要考虑一下Owner的粒度： 合约Owner,Collection Owner,Token Owner
            publicDataInfo.nftContract = publicDataContract;
        } else {
            require(dataMixedHash == IERC721VerfiyDataHash(publicDataContract).tokenDataHash(tokenId));
            publicDataInfo.nftContract = publicDataContract;
            publicDataInfo.tokenId = tokenId;
        }

        uint256 balance_add = (depositAmount * 8) / 10;
        publicDataInfo.data_balance += balance_add;
        uint256 system_reward = depositAmount - balance_add;

        _addCycleReward(system_reward);

        emit PublicDataCreated(dataMixedHash);
        emit SponserChanged(dataMixedHash, address(0), msg.sender);
        emit DepositData(msg.sender, dataMixedHash, balance_add, system_reward);
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
        require(publicDataInfo.maxDeposit > 0);
        require(publicDataInfo.owner == msg.sender);

        // transfer deposit
        gwtToken.transferFrom(msg.sender, address(this), depositAmount);

        uint256 balance_add = (depositAmount * 8) / 10;
        publicDataInfo.data_balance += balance_add;

        uint256 system_reward = depositAmount - balance_add;
        _addCycleReward(system_reward);

        if (depositAmount > ((publicDataInfo.maxDeposit * 11) / 10)) {
            publicDataInfo.maxDeposit = depositAmount;
            address oldSponser = publicDataInfo.sponsor;
            if(oldSponser != msg.sender) {
                publicDataInfo.sponsor = msg.sender;
                emit SponserChanged(dataMixedHash, oldSponser, msg.sender);
            }
        }

        emit DepositData(msg.sender, dataMixedHash, balance_add, system_reward);
    }

    function dataBalance(bytes32 dataMixedHash) public view returns(uint256) {
        return public_datas[dataMixedHash].data_balance;
    }

    function pledgeGwt(uint256 amount, bytes32 dataMixedHash) public {
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
        //TODO 这个质押保存的结构有点复杂了，可以简化
        // REVIEW by weiqiushi: 因为质押是针对数据的，所以才有两层索引。否则一个supplier可以通过质押一份空间来SHOW多份数据
        uint256 supplierPledge = supplier_pledge[supplierAddress].pledge[dataMixedHash];
        uint256 showReward = public_datas[dataMixedHash].data_balance / 10;
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
        // TODO:这里用this_block_show就好了，不用全保存下来
        // by weiqiushi: 什么是this_block_show？
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
        dataInfo.score += getDataSize(dataMixedHash);

        // insert supplier into last_showers
        if (dataInfo.shower_index >= 5) {
            dataInfo.shower_index = 0;
        }
        dataInfo.last_showers[dataInfo.shower_index] = supplier;
        dataInfo.shower_index += 1;
        
        //TODO：计算奖励前先判断用户是否有足够的非冻结抵押余额，Show完后会更新LastShowTime，以及冻结的质押余额
        // REVIEW by weiqiushi: 用户的质押余额会分冻结和非冻结？文档里没有这样的逻辑
        // 给成功的show一些奖励
        uint256 reward = publicDataInfo.data_balance / 10;
        if (reward > 0) {
            gwtToken.transfer(supplier, reward);
            publicDataInfo.data_balance -= reward;
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
    // TODO:challenge也可能会被挑战，所以不如简化成showData是上一个showData的挑战。
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

    function withdrawAward(uint cycleNumber, bytes32 dataMixedHash) public {
        // 判断这次的cycle已经结束
        require(block.number > cycleNumber * blocksPerCycle + startBlock);
        CycleInfo storage cycleInfo = cycle_infos[_cycleNumber()];
        CycleDataInfo storage dataInfo = cycleInfo.data_infos[dataMixedHash];
        //REVIEW:一次排序并保存的GAS和32次内存排序的成本问题？
        uint256 scoreListRanking = cycleInfo.score_list.getRanking(dataMixedHash);
        require(scoreListRanking > 0);

        // 看看是谁来取
        // REVIEW 这个函数做的事情比较多，建议拆分，或则命名更优雅一些
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


        emit WithdrawAward(dataMixedHash, msg.sender, reward);
    }
}
