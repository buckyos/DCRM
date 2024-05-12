// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./gwt.sol";
import "./sortedlist.sol";
import "./PublicDataProof.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "hardhat/console.sol";

using SortedScoreList for SortedScoreList.List;

//Review:这个作为ERC的一部分，要仔细考虑一下
interface IERCPublicDataContract {
    //return the owner of the data
    function getDataOwner(bytes32 dataHash) external view returns (address);
}
/*
interface IERC721VerifyDataHash{
    //return token data hash
    function tokenDataHash(uint256 _tokenId) external view returns (bytes32);
}
*/
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

contract PublicDataStorage is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    enum ShowType { Normal, Immediately }

    struct PublicData {
        address sponsor;
        address dataContract;
        uint256 maxDeposit;
        uint256 dataBalance;
        uint64 depositRatio;
        //uint64 point;
    }

    struct DataProof {
        uint256 nonceBlockHeight;
        uint256 proofBlockHeight;
        bytes32 proofResult;
        address prover;
        // ShowType showType;
        uint256 lockedAmount;
    }

    struct SupplierInfo {
        uint256 avalibleBalance;
        uint256 lockedBalance;
        uint256 unlockBlock;
        uint256 lastShowBlock;
    }

    GWT public gwtToken;// Gb per Week Token
    address public foundationAddress;

    mapping(address => SupplierInfo) _supplierInfos;
    mapping(bytes32 => PublicData) _publicDatas;
    mapping(uint256 => DataProof) _publicDataProofs;

    mapping(address => bool) _allowedPublicDataContract;

    struct CycleDataInfo {
        address[] lastShowers;
        uint64 score;// score = 0表示已经提现过了
        uint8 showerIndex;
    }

    struct CycleInfo {
        mapping(bytes32 => CycleDataInfo) dataInfos; 

        SortedScoreList.List scoreList;
        uint256 totalAward;    // 记录这个cycle的总奖励
    }

    struct CycleOutputInfo {
        uint256 totalReward;
        bytes32[] dataRanking;
    }

    //cycel nunber => cycle info
    uint256 _currectCycle;
    mapping(uint256 => CycleInfo) _cycleInfos;
    uint256 _startBlock;
    uint64 _minRankingScore;

    struct SysConfig {
        uint32 minDepositRatio;
        uint32 minPublicDataStorageWeeks;
        uint32 minLockWeeks;
        uint32 blocksPerCycle;
        uint32 topRewards;
        uint32 lockAfterShow;
        uint32 showTimeout;
        uint32 maxNonceBlockDistance;
        uint32 createDepositRatio;
        uint64 minRankingScore;
        uint64 minDataSize;
    }

    SysConfig public sysConfig;
    uint256 public totalRewardScore;

    event SupplierBalanceChanged(address supplier, uint256 avalibleBalance, uint256 lockedBalance);
    event GWTStacked(address supplier, uint256 amount);
    event GWTUnstacked(address supplier, uint256 amount);
    event PublicDataCreated(bytes32 mixedHash);
    event DepositData(address depositer, bytes32 mixedHash, uint256 balance, uint256 reward);
    event SponsorChanged(bytes32 mixedHash, address oldSponsor, address newSponsor);
    // event DataScoreUpdated(bytes32 mixedHash, uint256 cycle, uint64 score);
    event DataPointAdded(bytes32 mixedHash, uint64 point);
    event SupplierReward(address supplier, bytes32 mixedHash, uint256 amount);
    event SupplierPunished(address supplier, bytes32 mixedHash, uint256 amount);
    event ShowDataProof(address supplier, bytes32 dataMixedHash, uint256 nonce_block);
    event WithdrawReward(bytes32 mixedHash, uint256 cycle);
    event CycleStart(uint256 cycleNumber, uint256 startReward);

    function initialize(address _gwtToken, address _Foundation) public initializer {
        __PublicDataStorageUpgradable_init(_gwtToken, _Foundation);
    }

    function __PublicDataStorageUpgradable_init(address _gwtToken, address _Foundation) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);

        gwtToken = GWT(_gwtToken);
        _startBlock = block.number;
        _currectCycle = 0;
        foundationAddress = _Foundation;
        totalRewardScore = 1600;

        // 设置初始参数
        sysConfig.minDepositRatio = 64;             // create data时最小为64倍
        sysConfig.minPublicDataStorageWeeks = 96;   // create data时最小为96周
        sysConfig.minLockWeeks = 24;                // show的时候最小为24周，目前固定为最小值
        sysConfig.blocksPerCycle = 17280;           // 每个cycle为72小时
        sysConfig.topRewards = 32;                  // top 32名进榜
        sysConfig.lockAfterShow = 11520;            // show成功后48小时内才能解锁
        sysConfig.showTimeout = 5760;               // show之后24小时允许挑战
        sysConfig.maxNonceBlockDistance = 2;        // 允许的nonce block距离, 要小于256
        sysConfig.minRankingScore = 64;             // 最小的排名分数
        sysConfig.minDataSize = 1 << 27;            // dataSize换算GWT时，最小值为128M
        sysConfig.createDepositRatio = 5;           // 因为初期推荐使用Immediate Show，这里会设置成5倍，可以让前十几个show都可以立即成立
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {
        
    }

    function allowPublicDataContract(address[] calldata contractAddrs) public onlyOwner {
        for (uint i = 0; i < contractAddrs.length; i++) {
            _allowedPublicDataContract[contractAddrs[i]] = true;
        }
        
    }

    function denyPublicDataContract(address[] calldata contractAddrs) public onlyOwner {
        for (uint i = 0; i < contractAddrs.length; i++) {
            _allowedPublicDataContract[contractAddrs[i]] = false;
        }
    }

    function setSysConfig(SysConfig calldata config) public onlyOwner {
        // 这个函数调用频率很低，直接整个set了
        sysConfig = config;
    }

    function _getRewardScore(uint256 ranking) internal pure returns(uint8) {
        uint8[32] memory rewardScores = [
            240, 180, 150, 120, 100, 80, 60, 53, 42, 36,
            35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 
            24, 23, 22, 21, 20, 19, 18 ,17, 16, 15, 14
        ];
        if (ranking <= rewardScores.length) {
            return rewardScores[ranking - 1];
        } else {
            return 0;
        }
    }

    function _getRemainScore(uint256 length) internal pure returns(uint16) {
        uint16[33] memory remainScores = [
            1600, 1360, 1180, 1030, 910, 810,
            730,  670,  617,  575, 539, 504,
            470,  437,  405,  374, 344, 315,
            287,  260,  234,  209, 185, 162,
            140,  119,   99,   80,  62,  45,
            29,   14, 0
        ];

        return remainScores[length];
    }

    function _cycleNumber(uint256 blockNumber, uint256 startBlock) internal view returns(uint256) {
        uint cycleNumber = (blockNumber - startBlock) / sysConfig.blocksPerCycle;
        if (cycleNumber * sysConfig.blocksPerCycle + startBlock < blockNumber) {
            cycleNumber += 1;
        }
        return cycleNumber;
    }

    function _curCycleNumber() internal view returns(uint256) {
        return _cycleNumber(block.number, _startBlock);
    }

    // 通过记录一个最后的周期来解决周期之间可能有空洞的问题
    function _ensureCurrentCycleStart() internal returns (CycleInfo storage) {
        uint256 cycleNumber = _curCycleNumber();
        CycleInfo storage cycleInfo = _cycleInfos[cycleNumber];
        // 如果cycle的reward为0，说明这个周期还没有开始
        // 开始一个周期：从上个周期的奖励中拿20%
        if (cycleInfo.totalAward == 0) {
            uint256 lastCycleReward = _cycleInfos[_currectCycle].totalAward;
            // 5%作为基金会收入
            uint256 fundationIncome = lastCycleReward * 5 / 100;
            gwtToken.transfer(foundationAddress, fundationIncome);
            // 如果上一轮的获奖数据不足32个，剩余的奖金也滚动进此轮奖池
            uint16 remainScore = _getRemainScore(_cycleInfos[_currectCycle].scoreList.length());
            uint256 remainReward = lastCycleReward * 4 * remainScore / totalRewardScore / 5;

            cycleInfo.totalAward = lastCycleReward - (lastCycleReward * 4 / 5) - fundationIncome + remainReward;
            _currectCycle = cycleNumber;

            emit CycleStart(cycleNumber, cycleInfo.totalAward);
        }

        return cycleInfo;
    }

    
    function _addCycleReward(uint256 amount) private {
        CycleInfo storage cycleInfo = _ensureCurrentCycleStart();
        cycleInfo.totalAward += amount;
    }

    // 计算这些空间对应多少GWT，单位是wei
    // 不满128MB的按照128MB计算
    function _dataSizeToGWT(uint64 dataSize) internal view returns(uint256) {
        uint64 fixedDataSize = dataSize;
        if (fixedDataSize < sysConfig.minDataSize) {
            fixedDataSize = sysConfig.minDataSize;
        }
        return (uint256(fixedDataSize) * 10 ** 18) >> 30;
    }

    function createPublicData(
        bytes32 dataMixedHash,
        uint64 depositRatio,
        uint256 depositAmount, 
        address publicDataContract
    ) public {
        require(dataMixedHash != bytes32(0), "data hash is empty");
        require(_allowedPublicDataContract[publicDataContract], " data contract not allowed");
        require(IERCPublicDataContract(publicDataContract).getDataOwner(dataMixedHash) != address(0), "not found in data contract");

        // 质押率影响用户SHOW数据所需要冻结的质押
        require(depositRatio >= sysConfig.minDepositRatio, "deposit ratio is too small");
        // minAmount = 数据大小*GWT兑换比例*最小时长*质押率
        // get data size from data hash
        uint64 dataSize = PublicDataProof.lengthFromMixedHash(dataMixedHash);
        uint256 minAmount = depositRatio * _dataSizeToGWT(dataSize) * sysConfig.minPublicDataStorageWeeks * sysConfig.createDepositRatio;
        require(depositAmount >= minAmount, "deposit amount is too small");
        
        PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
        require(publicDataInfo.maxDeposit == 0, "public data already exists");

        publicDataInfo.depositRatio = depositRatio;
        publicDataInfo.maxDeposit = depositAmount;
        publicDataInfo.sponsor = msg.sender;
        publicDataInfo.dataContract = publicDataContract;
        gwtToken.transferFrom(msg.sender, address(this), depositAmount);

        uint256 balance_add = (depositAmount * 8) / 10;
        publicDataInfo.dataBalance += balance_add;
        uint256 system_reward = depositAmount - balance_add;

        _addCycleReward(system_reward);

        emit PublicDataCreated(dataMixedHash);
        emit SponsorChanged(dataMixedHash, address(0), msg.sender);
        emit DepositData(msg.sender, dataMixedHash, balance_add, system_reward);
    }

    function getPublicData(bytes32 dataMixedHash) public view returns(PublicData memory) {
        return _publicDatas[dataMixedHash];
    }

    function getCurrectLastShowed(bytes32 dataMixedHash) public view returns(address[] memory) {
        return _cycleInfos[_curCycleNumber()].dataInfos[dataMixedHash].lastShowers;
    }

    function getDataInCycle(uint256 cycleNumber, bytes32 dataMixedHash) public view returns(CycleDataInfo memory) {
        return _cycleInfos[cycleNumber].dataInfos[dataMixedHash];
    }

    function getCycleInfo(uint256 cycleNumber) public view returns(CycleOutputInfo memory) {
        return CycleOutputInfo(_cycleInfos[cycleNumber].totalAward, _cycleInfos[cycleNumber].scoreList.getSortedList());
    }

    function getPledgeInfo(address supplier) public view returns(SupplierInfo memory) {
        return _supplierInfos[supplier];
    }

    function isDataContractAllowed(address contractAddr) public view returns(bool) {
        return _allowedPublicDataContract[contractAddr];
    }

    function getOwner(bytes32 dataMixedHash) public view returns(address) {
        PublicData memory info = _publicDatas[dataMixedHash];
        return _getDataOwner(dataMixedHash, info);
    }

    function addDeposit(bytes32 dataMixedHash, uint256 depositAmount) public {
        PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
        require(publicDataInfo.maxDeposit > 0, "public data not exist");

        // transfer deposit
        gwtToken.transferFrom(msg.sender, address(this), depositAmount);

        uint256 balance_add = (depositAmount * 8) / 10;
        publicDataInfo.dataBalance += balance_add;

        uint256 system_reward = depositAmount - balance_add;
        _addCycleReward(system_reward);

        if (depositAmount > ((publicDataInfo.maxDeposit * 11) / 10)) {
            publicDataInfo.maxDeposit = depositAmount;
            address oldSponsor = publicDataInfo.sponsor;
            if(oldSponsor != msg.sender) {
                publicDataInfo.sponsor = msg.sender;
                emit SponsorChanged(dataMixedHash, oldSponsor, msg.sender);
            }
        }

        emit DepositData(msg.sender, dataMixedHash, balance_add, system_reward);
    }

    function dataBalance(bytes32 dataMixedHash) public view returns(uint256) {
        return _publicDatas[dataMixedHash].dataBalance;
    }

    function _adjustSupplierBalance(address supplier) internal {
        SupplierInfo storage supplierInfo = _supplierInfos[supplier];
        if (supplierInfo.unlockBlock < block.number) {
            supplierInfo.avalibleBalance += supplierInfo.lockedBalance;
            supplierInfo.lockedBalance = 0;
        }
    }

    function pledgeGwt(uint256 amount) public {
        gwtToken.transferFrom(msg.sender, address(this), amount);
        _supplierInfos[msg.sender].avalibleBalance += amount;

        emit SupplierBalanceChanged(msg.sender, _supplierInfos[msg.sender].avalibleBalance, _supplierInfos[msg.sender].lockedBalance);
    }

    function unstakeGWT(uint256 amount) public {
        // 如果用户的锁定余额可释放，这里会直接释放掉
        _adjustSupplierBalance(msg.sender);
        SupplierInfo storage supplierInfo = _supplierInfos[msg.sender];
        require(amount <= supplierInfo.avalibleBalance, "insufficient balance");
        supplierInfo.avalibleBalance -= amount;
        gwtToken.transfer(msg.sender, amount);
        emit SupplierBalanceChanged(msg.sender, supplierInfo.avalibleBalance, supplierInfo.lockedBalance);
    }

    function _getLockAmountByHash(bytes32 dataMixedHash, ShowType showType) internal view returns(uint256, bool) {
        uint64 dataSize = PublicDataProof.lengthFromMixedHash(dataMixedHash);
        uint256 immediatelyLockAmount = (showType == ShowType.Immediately) ? _publicDatas[dataMixedHash].dataBalance * 2 / 10 : 0;
        uint256 normalLockAmount = _dataSizeToGWT(dataSize) * _publicDatas[dataMixedHash].depositRatio * sysConfig.minLockWeeks;

        bool isImmediately = immediatelyLockAmount > normalLockAmount;

        return (isImmediately ? immediatelyLockAmount : normalLockAmount, isImmediately);
    }

    function _LockSupplierPledge(address supplierAddress, bytes32 dataMixedHash, ShowType showType) internal returns(uint256, bool){
        _adjustSupplierBalance(supplierAddress);
        
        SupplierInfo storage supplierInfo = _supplierInfos[supplierAddress];
        
        (uint256 lockAmount, bool isImmediately) = _getLockAmountByHash(dataMixedHash, showType);
        
        require(supplierInfo.avalibleBalance >= lockAmount, "insufficient balance");
        supplierInfo.avalibleBalance -= lockAmount;
        supplierInfo.lockedBalance += lockAmount;
        supplierInfo.unlockBlock = block.number + sysConfig.lockAfterShow;
        emit SupplierBalanceChanged(supplierAddress, supplierInfo.avalibleBalance, supplierInfo.lockedBalance);
        return (lockAmount, isImmediately);
    }

    function _verifyDataProof(bytes32 dataMixedHash,uint256 nonce_block, uint32 index, bytes16[] calldata m_path, bytes calldata leafdata) private view returns(bytes32,bytes32) {
        require(nonce_block < block.number, "invalid nonce_block_high");
        require(block.number - nonce_block < 256, "nonce block too old");

        bytes32 nonce = blockhash(nonce_block);

        return PublicDataProof.calcDataProof(dataMixedHash, nonce, index, m_path, leafdata, bytes32(0));
    }

    function _mergeMixHashAndHeight(uint256 dataMixedHash, uint256 nonce_block) public pure returns (uint256) {
        uint256 highBits = dataMixedHash >> 64; 
        uint256 lowBits = nonce_block & ((1 << 64) - 1); 
        return (highBits << 64) | lowBits; 
    }

    function _scoreFromHash(bytes32 dataMixedHash) public pure returns (uint64) {
        uint256 size = PublicDataProof.lengthFromMixedHash(dataMixedHash) >> 30;
        if (size == 0) {
            // 1GB以下算1分
            return 1;
        }
        return uint64(size / 4 + 2);
    }

    function _updateLastSupplier(CycleDataInfo storage dataInfo, address oldSupplier, address supplier) private {
        if (oldSupplier != address(0)) {
            for (uint8 i = 0; i < dataInfo.lastShowers.length; i++) {
                if (dataInfo.lastShowers[i] == oldSupplier) {
                    dataInfo.lastShowers[i] = supplier;
                    break;
                }
            }
        } else {
            if (dataInfo.lastShowers.length < 5) {
                dataInfo.lastShowers.push(supplier);
            } else {
                dataInfo.lastShowers[dataInfo.showerIndex] = supplier;
                dataInfo.showerIndex += 1;
            }

            if (dataInfo.showerIndex >= 5) {
                dataInfo.showerIndex = 0;
            }
        }
        
    }

    function _onProofSuccess(DataProof storage proof,PublicData storage publicDataInfo,bytes32 dataMixedHash) private {
        uint256 reward = publicDataInfo.dataBalance / 10;
        emit SupplierReward(proof.prover, dataMixedHash, reward);
        if (reward > 0) {
            gwtToken.transfer(proof.prover, reward);
            publicDataInfo.dataBalance -= reward;
        }

        // 更新本cycle的score
        CycleInfo storage cycleInfo = _ensureCurrentCycleStart();
        CycleDataInfo storage dataInfo = cycleInfo.dataInfos[dataMixedHash];
        
        // 按文件大小比例增加 ， 0.1G - 1G 1分，1G-4G 2分， 4G-8G 3分，8G-16G 4分 16G-32G 5分 ...  
        uint64 score = _scoreFromHash(dataMixedHash);
        dataInfo.score += score;

        //emit DataScoreUpdated(dataMixedHash, _curCycleNumber(), score);
        emit DataPointAdded(dataMixedHash, score);

        // 合约里不关注的数据先不记录了，省gas
        //publicDataInfo.point += score;
        
        // 更新cycle的last shower
        _updateLastSupplier(dataInfo, address(0), msg.sender);

        //只有超过阈值才会更新排名，这个设定会导致用户不多的时候排名不满（强制性累积奖金）
        if (dataInfo.score > sysConfig.minRankingScore) {
            if (cycleInfo.scoreList.maxlen() < sysConfig.topRewards) {
                cycleInfo.scoreList.setMaxLen(sysConfig.topRewards);
            }
            cycleInfo.scoreList.updateScore(dataMixedHash, dataInfo.score);
        }
    }

    function getDataProof(bytes32 dataMixedHash, uint256 nonce_blocks) public view returns(DataProof memory) {
        uint256 proofKey = _mergeMixHashAndHeight(uint256(dataMixedHash), nonce_blocks);
        return _publicDataProofs[proofKey];
    }

    function withdrawShow(bytes32 dataMixedHash, uint256 nonce_block) public {
        uint256 proofKey = _mergeMixHashAndHeight(uint256(dataMixedHash), nonce_block);
        DataProof storage proof = _publicDataProofs[proofKey];

        require(proof.proofBlockHeight > 0, "proof not exist");
        require(block.number - proof.proofBlockHeight > sysConfig.showTimeout, "proof not unlock");

        if (block.number - proof.proofBlockHeight > sysConfig.showTimeout) {
            //Last Show Proof successed! 获得奖励+增加积分
            PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
            _onProofSuccess(proof, publicDataInfo,dataMixedHash);
        
            //防止重入：反复领取奖励
            proof.proofBlockHeight = 0;
        }
    }

    function showData(bytes32 dataMixedHash, uint256 nonce_block, uint32 index, bytes16[] calldata m_path, bytes calldata leafdata, ShowType showType) public {
        uint256 proofKey = _mergeMixHashAndHeight(uint256(dataMixedHash), nonce_block);
        DataProof storage proof = _publicDataProofs[proofKey];
        
        bool isNewShow = false;
        address supplier = msg.sender;

        if(proof.proofBlockHeight == 0) {
            require(block.number - nonce_block <= sysConfig.maxNonceBlockDistance, "invalid nonce block");
            isNewShow = true;
        } else {
            require(block.number - proof.proofBlockHeight <= sysConfig.showTimeout, "challenge timeout");
        }
    
        (bytes32 root_hash,) = _verifyDataProof(dataMixedHash,nonce_block,index,m_path,leafdata);

        if(isNewShow) {
            //根据showType决定锁定金额
            PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
            (uint256 lockAmount, bool isImmediately) = _LockSupplierPledge(supplier, dataMixedHash, showType);

            proof.lockedAmount = lockAmount;
            proof.nonceBlockHeight = nonce_block;
            proof.proofResult = root_hash;
            proof.proofBlockHeight = block.number;
            proof.prover = msg.sender;
            //proof.showType = showType;

            if(isImmediately) {
                _onProofSuccess(proof, publicDataInfo, dataMixedHash);
            }

        } else {
            // 已经有挑战存在：判断是否结果更好，如果更好，更新结果，并更新区块高度
            if(root_hash < proof.proofResult) {
                _supplierInfos[proof.prover].lockedBalance -= proof.lockedAmount;

                uint256 rewardFromPunish = proof.lockedAmount * 8 / 10;
                gwtToken.transfer(msg.sender, rewardFromPunish);
                gwtToken.transfer(foundationAddress, proof.lockedAmount - rewardFromPunish);
                
                emit SupplierPunished(proof.prover, dataMixedHash, proof.lockedAmount);
                emit SupplierBalanceChanged(proof.prover, _supplierInfos[proof.prover].avalibleBalance, _supplierInfos[proof.prover].lockedBalance);

                PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
                (uint256 lockAmount, bool isImmediately) = _LockSupplierPledge(supplier, dataMixedHash, showType);

                if(isImmediately) {
                    _onProofSuccess(proof, publicDataInfo, dataMixedHash);
                }

                proof.lockedAmount = lockAmount;
                proof.proofResult = root_hash;
                proof.proofBlockHeight = block.number;
                proof.prover = msg.sender;
                //proof.showType = showType;
            } 
        }

        emit ShowDataProof(msg.sender, dataMixedHash, nonce_block);
    }

    function _getDataOwner(bytes32 dataMixedHash, PublicData memory publicDataInfo) internal view returns(address) {
        return IERCPublicDataContract(publicDataInfo.dataContract).getDataOwner(dataMixedHash);
    }

    function withdrawReward(uint256 cycleNumber, bytes32 dataMixedHash) public {
        // 判断这次的cycle已经结束
        //require(_currectCycle > cycleNumber, "cycle not finish");
        require(block.number > cycleNumber * sysConfig.blocksPerCycle + _startBlock, "cycle not finish");
        CycleInfo storage cycleInfo = _cycleInfos[cycleNumber];
        CycleDataInfo storage dataInfo = cycleInfo.dataInfos[dataMixedHash];
        //REVIEW:一次排序并保存的GAS和32次内存排序的成本问题？
        uint256 scoreListRanking = cycleInfo.scoreList.getRanking(dataMixedHash);
        require(scoreListRanking > 0, "data not in rank");

        // 无论谁来取，一次性提取所有奖励，并更新积分
        require(dataInfo.score > 0, "already withdraw");

        // 计算该得到多少奖励
        uint256 totalReward = cycleInfo.totalAward * 8 / 10;

        uint8 score = _getRewardScore(scoreListRanking);
        // 如果数据总量不足32，那么多余的奖励沉淀在合约账户中
        uint256 dataReward = totalReward * score / totalRewardScore;

        // memory无法创建动态数组和map，直接算一个转一个了

        // owner
        gwtToken.transfer(_getDataOwner(dataMixedHash, _publicDatas[dataMixedHash]), dataReward / 5);

        // sponser
        gwtToken.transfer(_publicDatas[dataMixedHash].sponsor, dataReward / 2);

        // last showers
        uint256 showerReward = (dataReward - dataReward / 2 - dataReward / 5) / dataInfo.lastShowers.length;
        for (uint8 i = 0; i < dataInfo.lastShowers.length; i++) {
            gwtToken.transfer(dataInfo.lastShowers[i], showerReward);
        }
        
        // 设置已取标志
        dataInfo.score = 0;

        // 更新积分
        emit DataPointAdded(dataMixedHash, score);
        emit WithdrawReward(dataMixedHash, cycleNumber);
    }
}
