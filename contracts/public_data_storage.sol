// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./gwt.sol";
import "./sortedlist.sol";
import "./PublicDataProof.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./ABDKMath64x64.sol";

import "hardhat/console.sol";

using SortedScoreList for SortedScoreList.List;
using ABDKMath64x64 for int128;

//Review: This is a part of ERC, consider it carefully
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
// Review: Considering that there are some chains of block time uncertain, the block interval should be cautious. You can use the timestamp of the block

// mixedDataHash: 2bit hash algorithm + 62bit data size + 192bit data hash
// 2bit hash algorithm: 00: keccak256, 01: sha256

/**
* Receive logic:
* Reward per cycle = reward of the previous cycle * 0.2 + All sponsorship in this cycle * 0.2
* Therefore, at each income reward, update the reward quota of this cycle
* When the quota of this cycle is 0, the reward of the above cycle* 0.2 starts
* Maybe accuracy loss?
*/

contract PublicDataStorage is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    enum ShowType {
        Normal,
        Immediately
    }

    struct PublicData {
        address sponsor;
        address dataContract;
        uint256 maxDeposit;
        uint256 dataBalance;
        uint64 pledgeRate;
        mapping(address => uint256) show_records; //miner address - > last show time
    }

    struct PublicDataForOutput {
        address sponsor;
        address dataContract;
        uint256 maxDeposit;
        uint256 dataBalance;
        uint64 depositRatio;
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

    GWT public gwtToken; // Gb per Week Token
    address public foundationAddress;

    mapping(address => SupplierInfo) _supplierInfos;
    mapping(bytes32 => PublicData) _publicDatas;
    mapping(uint256 => DataProof) _publicDataProofs;

    mapping(address => bool) _allowedPublicDataContract;

    struct CycleDataInfo {
        address[] lastShowers;
        uint64 score; //score = 0 means that it has been withdrawn
        uint8 showerIndex;
        uint64 showCount; //Total show in this cycle,
    }

    struct CycleInfo {
        mapping(bytes32 => CycleDataInfo) dataInfos;
        SortedScoreList.List scoreList;
        uint256 totalAward; // Record the total reward of this Cycle
        uint256 totalShowPower; //Record the support of this cycle
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
        uint32 minPledgeRate;
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
        uint256 minImmediatelyLockAmount;
    }

    SysConfig public sysConfig;
    uint256 public totalRewardScore;

    event SupplierBalanceChanged(
        address supplier,
        uint256 avalibleBalance,
        uint256 lockedBalance
    );
    event GWTStacked(address supplier, uint256 amount);
    event GWTUnstacked(address supplier, uint256 amount);
    event PublicDataCreated(bytes32 mixedHash);
    event DepositData(
        address depositer,
        bytes32 mixedHash,
        uint256 balance,
        uint256 reward
    );
    event SponsorChanged(
        bytes32 mixedHash,
        address oldSponsor,
        address newSponsor
    );
    // event DataScoreUpdated(bytes32 mixedHash, uint256 cycle, uint64 score);
    event DataPointAdded(bytes32 mixedHash, uint64 point);
    event SupplierReward(address supplier, bytes32 mixedHash, uint256 amount);
    event SupplierPunished(address supplier, bytes32 mixedHash, uint256 amount);
    event ShowDataProof(
        address supplier,
        bytes32 dataMixedHash,
        uint256 nonce_block
    );
    event WithdrawReward(bytes32 mixedHash, uint256 cycle);
    event CycleStart(uint256 cycleNumber, uint256 startReward);

    function initialize(
        address _gwtToken,
        address _Foundation
    ) public initializer {
        __PublicDataStorageUpgradable_init(_gwtToken, _Foundation);
    }

    function __PublicDataStorageUpgradable_init(
        address _gwtToken,
        address _Foundation
    ) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);

        gwtToken = GWT(_gwtToken);
        _startBlock = block.number;
        _currectCycle = 2;
        foundationAddress = _Foundation;
        totalRewardScore = 1600;

        sysConfig.minPledgeRate = 64; // Create data is the minimum of 64 times
        sysConfig.minPublicDataStorageWeeks = 96; //Create data is the minimum of 96 weeks
        sysConfig.minLockWeeks = 24; // sThe minimum is 24 weeks when it is at the current fixed value
        sysConfig.blocksPerCycle = 86400; // Each cycle is 72 hours
        sysConfig.topRewards = 32; // TOP 32 entry list
        sysConfig.lockAfterShow = 57600; // You can unlock it within 48 hours after show
        sysConfig.showTimeout = 4800; // 4 hours after show, allow challenges
        sysConfig.maxNonceBlockDistance = 10; // The allowable Nonce Block distance is less than 256
        sysConfig.minRankingScore = 64; // The smallest ranking
        sysConfig.minDataSize = 1 << 27; // When DataSize conversion GWT, the minimum value is 128M
        sysConfig.createDepositRatio = 3; // Because IMMEDIATE Show is recommended in the early stage, it will be set to 5 times here, so that the top ten shows can be established immediately
        sysConfig.minImmediatelyLockAmount = 210; // The minimum amount of IMMEDIATELY lock
    }


    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}

    function allowPublicDataContract(
        address[] calldata contractAddrs
    ) public onlyOwner {
        for (uint i = 0; i < contractAddrs.length; i++) {
            _allowedPublicDataContract[contractAddrs[i]] = true;
        }
    }

    function denyPublicDataContract(
        address[] calldata contractAddrs
    ) public onlyOwner {
        for (uint i = 0; i < contractAddrs.length; i++) {
            _allowedPublicDataContract[contractAddrs[i]] = false;
        }
    }

    //TODO:Who is eligible to update the key parameters of the system? After testing (after a period of time), SYSCONFIG can be modified
    function setSysConfig(SysConfig calldata config) public onlyOwner {
        sysConfig = config;
    }

    function _getRewardScore(uint256 ranking) internal pure returns (uint8) {
        uint8[32] memory rewardScores = [
            240,
            180,
            150,
            120,
            100,
            80,
            60,
            53,
            42,
            36,
            35,
            34,
            33,
            32,
            31,
            30,
            29,
            28,
            27,
            26,
            25,
            24,
            23,
            22,
            21,
            20,
            19,
            18,
            17,
            16,
            15,
            14
        ];
        if (ranking <= rewardScores.length) {
            return rewardScores[ranking - 1];
        } else {
            return 0;
        }
    }

    function _getRemainScore(uint256 length) internal pure returns (uint16) {
        uint16[33] memory remainScores = [
            1600,
            1360,
            1180,
            1030,
            910,
            810,
            730,
            670,
            617,
            575,
            539,
            504,
            470,
            437,
            405,
            374,
            344,
            315,
            287,
            260,
            234,
            209,
            185,
            162,
            140,
            119,
            99,
            80,
            62,
            45,
            29,
            14,
            0
        ];

        return remainScores[length];
    }

    function _cycleNumber(
        uint256 blockNumber,
        uint256 startBlock
    ) internal view returns (uint256) {
        uint cycleNumber = (blockNumber - startBlock) /
            sysConfig.blocksPerCycle;
        if (cycleNumber * sysConfig.blocksPerCycle + startBlock < blockNumber) {
            cycleNumber += 1;
        }
        return cycleNumber + 1;
    }

    function _curCycleNumber() internal view returns (uint256) {
        return _cycleNumber(block.number, _startBlock);
    }

    // By recording a final cycle, there may be empty cycle problems between cycles
    function _ensureCurrentCycleStart() internal returns (CycleInfo storage) {
        uint256 cycleNumber = _curCycleNumber();
        CycleInfo storage cycleInfo = _cycleInfos[cycleNumber];
        // If Cycle's reward is 0, it means that this cycle has not yet begun
        // Start a cycle: 20% from the reward of the previous cycle
        if (cycleInfo.totalAward == 0) {
            uint256 lastCycleReward = _cycleInfos[_currectCycle].totalAward;
            // 5%as a foundation income
            uint256 fundationIncome = (lastCycleReward * 5) / 100;
            gwtToken.transfer(foundationAddress, fundationIncome);
            // If the last round of the award -winning data is less than 32, the remaining bonuses are also rolled into this round prize pool
            uint16 remainScore = _getRemainScore(
                _cycleInfos[_currectCycle].scoreList.length()
            );
            uint256 remainReward = (lastCycleReward * 4 * remainScore) / totalRewardScore / 5;

            cycleInfo.totalAward = lastCycleReward - ((lastCycleReward * 4) / 5) - fundationIncome + remainReward;
            _currectCycle = cycleNumber;

            emit CycleStart(cycleNumber, cycleInfo.totalAward);
        }

        return cycleInfo;
    }

    function _addCycleReward(uint256 amount) private {
        CycleInfo storage cycleInfo = _ensureCurrentCycleStart();
        cycleInfo.totalAward += amount;
    }

    // Calculate how much GWT corresponds to these spaces, the unit is wei
    // Under 128MB, calculate at 128MB
    function _dataSizeToGWT(uint64 dataSize) internal view returns (uint256) {
        uint64 fixedDataSize = dataSize;
        if (fixedDataSize < sysConfig.minDataSize) {
            fixedDataSize = sysConfig.minDataSize;
        }
        return (uint256(fixedDataSize) * 10 ** 18) >> 30;
    }

    /**
    * @dev Create(Register) public data, To become public data, any data needs to be registered in public data contracts first
    * @param dataMixedHash The hash of the data
    * @param pledgeRate The pledge rate of the data
    * @param depositAmount The pledge amount of the data
    *        depositAmount >= data size*gwt exchange ratio*minimum hour length*pledgeRate
    * @param publicDataContract The address of the NFT contract
    *        This NFT Contract must implement the IERCPublicDataContract interface,can get the owner of the data
    */
    function createPublicData(
        bytes32 dataMixedHash,
        uint64 pledgeRate,
        uint256 depositAmount,
        address publicDataContract
    ) public {
        require(dataMixedHash != bytes32(0), "data hash is empty");
        require(
            _allowedPublicDataContract[publicDataContract],
            " data contract not allowed"
        );
        require(
            IERCPublicDataContract(publicDataContract).getDataOwner(dataMixedHash) != address(0),
            "not found in data contract"
        );

        // The pledge rate affects the pledge that the user's Show data needs to be frozen
        require(
            pledgeRate >= sysConfig.minPledgeRate,
            "deposit ratio is too small"
        );
        // minamount = data size*gwt exchange ratio*minimum hour length*pledge rate
        // get data size from data hash
        uint64 dataSize = PublicDataProof.lengthFromMixedHash(dataMixedHash);
        uint256 minAmount = pledgeRate *
            _dataSizeToGWT(dataSize) *
            sysConfig.minPublicDataStorageWeeks *
            sysConfig.createDepositRatio;
        require(depositAmount >= minAmount, "deposit amount is too small");

        PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
        require(publicDataInfo.maxDeposit == 0, "public data already exists");

        publicDataInfo.pledgeRate = pledgeRate;
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


    function getPublicData(
        bytes32 dataMixedHash
    ) public view returns (PublicDataForOutput memory) {
        PublicData storage info = _publicDatas[dataMixedHash];
        return PublicDataForOutput(
            info.sponsor,
            info.dataContract,
            info.maxDeposit,
            info.dataBalance,
            info.pledgeRate
        );
    }

    function getCurrectLastShowed(
        bytes32 dataMixedHash
    ) public view returns (address[] memory) {
        return
            _cycleInfos[_curCycleNumber()].dataInfos[dataMixedHash].lastShowers;
    }

    function getDataInCycle(
        uint256 cycleNumber,
        bytes32 dataMixedHash
    ) public view returns (CycleDataInfo memory) {
        return _cycleInfos[cycleNumber].dataInfos[dataMixedHash];
    }

    function getCycleInfo(
        uint256 cycleNumber
    ) public view returns (CycleOutputInfo memory) {
        return
            CycleOutputInfo(
                _cycleInfos[cycleNumber].totalAward,
                _cycleInfos[cycleNumber].scoreList.getSortedList()
            );
    }

    function getPledgeInfo(
        address supplier
    ) public view returns (SupplierInfo memory) {
        return _supplierInfos[supplier];
    }

    function isDataContractAllowed(
        address contractAddr
    ) public view returns (bool) {
        return _allowedPublicDataContract[contractAddr];
    }

    function getOwner(bytes32 dataMixedHash) public view returns (address) {
        return _getDataOwner(dataMixedHash, _publicDatas[dataMixedHash]);
    }

    
    /**
     * @dev Adds a deposit to the public data storage,If this recharge exceeds 10%of the maximum recharge amount, the sponser that updates the public data is msg.sender
     * @param dataMixedHash The hash of the mixed data.
     * @param depositAmount The amount of the deposit.
     */
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
            if (oldSponsor != msg.sender) {
                publicDataInfo.sponsor = msg.sender;
                emit SponsorChanged(dataMixedHash, oldSponsor, msg.sender);
            }
        }

        emit DepositData(msg.sender, dataMixedHash, balance_add, system_reward);
    }

    function dataBalance(bytes32 dataMixedHash) public view returns (uint256) {
        return _publicDatas[dataMixedHash].dataBalance;
    }

    function _adjustSupplierBalance(address supplier) internal {
        SupplierInfo storage supplierInfo = _supplierInfos[supplier];
        if (supplierInfo.unlockBlock < block.number) {
            supplierInfo.avalibleBalance += supplierInfo.lockedBalance;
            supplierInfo.lockedBalance = 0;
        }
    }

    /**
     * @dev Package GWT and become a supplier, you can show public data after becoming SUPPLIER
     * @param amount The amount of GWT to be pledged
     */
    function pledgeGwt(uint256 amount) public {
        gwtToken.transferFrom(msg.sender, address(this), amount);
        _supplierInfos[msg.sender].avalibleBalance += amount;

        emit SupplierBalanceChanged(
            msg.sender,
            _supplierInfos[msg.sender].avalibleBalance,
            _supplierInfos[msg.sender].lockedBalance
        );
    }

    /**
     * @dev Unstake GWT, the avalible pledge GWT can be withdrawn at any time
     * @param amount The amount of GWT to be withdrawn
     */
    function unstakeGWT(uint256 amount) public {
        // If the user’s lock balance can be released, it will be released directly
        _adjustSupplierBalance(msg.sender);
        SupplierInfo storage supplierInfo = _supplierInfos[msg.sender];
        require(amount <= supplierInfo.avalibleBalance, "insufficient balance");
        supplierInfo.avalibleBalance -= amount;
        gwtToken.transfer(msg.sender, amount);
        emit SupplierBalanceChanged(
            msg.sender,
            supplierInfo.avalibleBalance,
            supplierInfo.lockedBalance
        );
    }

    function _getLockAmountByHash(
        bytes32 dataMixedHash,
        ShowType showType
    ) internal view returns (uint256, bool) {
        uint64 dataSize = PublicDataProof.lengthFromMixedHash(dataMixedHash);
        uint256 normalLockAmount = _dataSizeToGWT(dataSize) *
            _publicDatas[dataMixedHash].pledgeRate *
            sysConfig.minLockWeeks;
        if(showType == ShowType.Immediately) {
            uint256 immediatelyLockAmount = (_publicDatas[dataMixedHash].dataBalance * 2) / 10;
            immediatelyLockAmount < sysConfig.minImmediatelyLockAmount ? sysConfig.minImmediatelyLockAmount : immediatelyLockAmount;
            return (normalLockAmount + immediatelyLockAmount, true);
        } else {
            return (normalLockAmount, false);
        }
    }

    function _LockSupplierPledge(
        address supplierAddress,
        bytes32 dataMixedHash,
        ShowType showType
    ) internal returns (uint256, bool) {
        _adjustSupplierBalance(supplierAddress);

        SupplierInfo storage supplierInfo = _supplierInfos[supplierAddress];

        (uint256 lockAmount, bool isImmediately) = _getLockAmountByHash(
            dataMixedHash,
            showType
        );

        require(
            supplierInfo.avalibleBalance >= lockAmount,
            "insufficient balance"
        );
        supplierInfo.avalibleBalance -= lockAmount;
        supplierInfo.lockedBalance += lockAmount;
        supplierInfo.unlockBlock = block.number + sysConfig.lockAfterShow;
        emit SupplierBalanceChanged(
            supplierAddress,
            supplierInfo.avalibleBalance,
            supplierInfo.lockedBalance
        );
        return (lockAmount, isImmediately);
    }

    function _verifyDataProof(
        bytes32 dataMixedHash,
        uint256 nonce_block,
        uint32 index,
        bytes16[] calldata m_path,
        bytes calldata leafdata
    ) private view returns (bytes32, bytes32) {
        require(nonce_block < block.number, "invalid nonce_block_high");
        require(block.number - nonce_block < 256, "nonce block too old");

        bytes32 nonce = blockhash(nonce_block);

        return
            PublicDataProof.calcDataProof(
                dataMixedHash,
                nonce,
                index,
                m_path,
                leafdata,
                bytes32(0)
            );
    }

    function _mergeMixHashAndHeight(
        uint256 dataMixedHash,
        uint256 nonce_block
    ) public pure returns (uint256) {
        uint256 highBits = dataMixedHash >> 64;
        uint256 lowBits = nonce_block & ((1 << 64) - 1);
        return (highBits << 64) | lowBits;
    }

    function _scoreFromHash(
        bytes32 dataMixedHash
    ) public pure returns (uint64) {
        uint256 size = PublicDataProof.lengthFromMixedHash(dataMixedHash) >> 30;
        if (size == 0) {
            // 1GB以下算1分
            return 1;
        }
        return uint64(size / 4 + 2);
    }

    function _updateLastSupplier(
        CycleDataInfo storage dataInfo,
        address oldSupplier,
        address supplier
    ) private {
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

    // Since the unit of CyclePower is GB, first expand 1024*1024*1000, and then calculate
    function _getGWTDifficultRatio(uint256 lastCyclePower, uint256 curCyclePower) public pure returns (uint256) {
    // This function is essentially, the weekly interest rate is returned
    // 1) Calculate the basic difficulty values ​​according to the total power. Each time the computing power doubles, the basic difficulty value will decrease from <= 1pb, 2pb, 4pb, 8pb, 16pb, 32pb, 64pb, 128pb, 256pb, 512pb ..Adjust the foundation difficulty
    // The multiplier result is 8X -1X. When the total power is 1PB (GWT), the multiplier rate is 8X, and the computing power then doubles, and the magnification decreases by 10%.Multiple rate = 0.9^(log2 (support/1pb)), double the total power each time, the multiplier is 90%
    // After the difficulty adjustment of about 21 times, it will become 1x. At this time, the system capacity is already 1pb * 2^21 = 2EB
    // 2) Calculate the benchmark GWT interest rate (increasing speed) according to the computing power growth X, y = f (x), and the value domain of x is from [0, positive infinity] y to be the minimum value of 0.2%, the maximum, the maximum, the maximum, the maximum, the maximumValue is 2%

    // According to the above rules, the largest GWT mining ratio is the largest, 16%of the total mortgage (16%of the weekly return).That is, the miners pledged 100 GWTs in public data mining. After 1 week, they could dig out 16 GWT, which is close to 6.25 weeks.
    // If the total computing power is low in the early days, but no one digs it, the weekly return is 1.6%(1.6%of the weekly return), that is, the miners pledged 100 GWTs in public data mining.1.6 GWT, close to 62.5 weeks back       //uint256 base_r = 0.002;
        uint256 base_r = 2097152;
        if (curCyclePower == 0) {
            // base_r = 0.01
            base_r = 10485760;
        } else {
           // A mathematical function, satisfying: y = f (x), the meaning of X is that the value domain of the growth rate is from [0, positive infinity] Y's value range is 0.2%, and the maximum value is 2%.I hope that before X is 200%(2 times), Y can quickly increase to 1%
            if (curCyclePower > lastCyclePower) {
                base_r += (8 * (curCyclePower - lastCyclePower) * 1024 * 1024 * 1000) / lastCyclePower;
                //base_r = 0.002 + (0.008 * (curCyclePower - lastCyclePower)) / lastCyclePower;
                if (base_r > 20971520) {
                    base_r = 20971520;
                }
            }
        }
        // 8 * 0.9^(log2((curCyclePower / 1PB)));
        // CurcyclePower's units are GB
        int128 exp1 = ABDKMath64x64.fromUInt(curCyclePower).log_2().toInt() - 20;
        if (exp1 < 0) {
            exp1 = 0;
        }
        uint256 ratio = ABDKMath64x64.divu(9, 10).pow(uint256(int256(exp1))).toUInt() * 8;
        //uint256 ratio = 8 * ((9/10)^(log2(curCyclePower / 1024 / 1024)));
        //              = 8 * 0.9^(log2(curCyclePower) - 20)
        if (ratio < 1) {
            ratio = 1;
        }
        return ratio * base_r;
    }

    function _onProofSuccess(
        DataProof storage proof,
        PublicData storage publicDataInfo,
        bytes32 dataMixedHash
    ) private {
        uint256 reward = publicDataInfo.dataBalance / 10;
        emit SupplierReward(proof.prover, dataMixedHash, reward);
        if (reward > 0) {
            gwtToken.transfer(proof.prover, reward);
            publicDataInfo.dataBalance -= reward;
        }

        // Update the score of this Cycle
        CycleInfo storage cycleInfo = _ensureCurrentCycleStart();
        CycleDataInfo storage dataInfo = cycleInfo.dataInfos[dataMixedHash];

        //Increase according to the proportion of file size ， 0.1G - 1G 1，1G-4G 2， 4G-8G 3，8G-16G 4 16G-32G 5 ...
        uint64 score = _scoreFromHash(dataMixedHash);
        dataInfo.score += score;

        //emit DataScoreUpdated(dataMixedHash, _curCycleNumber(), score);
        emit DataPointAdded(dataMixedHash, score);


        // Update Cycle's Last Shower
        _updateLastSupplier(dataInfo, address(0), msg.sender);

        //Only exceeding the threshold will update the ranking. This setting will cause the user to be dissatisfied when there are not many users (forced cumulative bonuses)
        if (dataInfo.score > sysConfig.minRankingScore) {
            if (cycleInfo.scoreList.maxlen() < sysConfig.topRewards) {
                cycleInfo.scoreList.setMaxLen(sysConfig.topRewards);
            }
            cycleInfo.scoreList.updateScore(dataMixedHash, dataInfo.score);
        }

        
        uint256 lastRecordShowTime = publicDataInfo.show_records[msg.sender];
        if (lastRecordShowTime == 0) {
            publicDataInfo.show_records[msg.sender] = block.timestamp;
        } else {
            //The second SHOW! Get GWT mining award
            if (block.timestamp - lastRecordShowTime > 1 weeks) {
                //获得有效算力!
                // reward = 文件大小* T * 存储质量比率（含质押率） * 公共数据挖矿难度比
                // T = 当前时间 - 上次show时间，T必须大于1周，最长为4周
                publicDataInfo.show_records[msg.sender] = block.timestamp;
                uint256 storageWeeks = (block.timestamp - lastRecordShowTime) / 1 weeks;
                if (storageWeeks > 4) {
                    storageWeeks = 4;
                }
                uint256 size = PublicDataProof.lengthFromMixedHash(dataMixedHash) >> 30;
                if (size == 0) {
                    // 1GB以下算1G
                    size = 1;
                }

                uint256 storagePower = size * storageWeeks;
                //更新当前周期的总算力，公共数据的算力是私有数据的3倍
                cycleInfo.totalShowPower += storagePower * 3;

                //计算挖矿奖励，难度和当前算力总量，上一个周期的算力总量有关
                // 如果_currectCycle是0或者1，这个要怎么算？
                uint256 lastCyclePower = _cycleInfos[_currectCycle - 2].totalShowPower;
                uint256 curCyclePower = _cycleInfos[_currectCycle - 1].totalShowPower;
                // 由于_getGWTDifficultRatio的返回扩大了1024*1024*1000倍，这里要除去
                uint256 gwtReward = storagePower *publicDataInfo.pledgeRate * _getGWTDifficultRatio(lastCyclePower, curCyclePower) / 1024 / 1024 / 1000;

                //更新奖励，80%给矿工，20%给当前数据的余额
                gwtToken.mint(msg.sender, gwtReward * 8 / 10);
                //TODO:是否需要留一部分挖矿奖励给基金会？目前思考是不需要的
                gwtToken.mint(address(this), gwtReward * 2 / 10);
                publicDataInfo.dataBalance += gwtReward * 2 / 10;
            }
        }
    }

    function getDataProof(
        bytes32 dataMixedHash,
        uint256 nonce_blocks
    ) public view returns (DataProof memory) {
        uint256 proofKey = _mergeMixHashAndHeight(
            uint256(dataMixedHash),
            nonce_blocks
        );
        return _publicDataProofs[proofKey];
    }

    /**
     * @dev Withdraw the SHOW reward of the data (challenge timeout)
     * @param dataMixedHash The hash of the data
     * @param nonce_block The block height of the random number NONCE of this show, the height of this block must be less than the current block height, and within the appropriate time range
     */
    function withdrawShow(bytes32 dataMixedHash, uint256 nonce_block) public {
        uint256 proofKey = _mergeMixHashAndHeight(
            uint256(dataMixedHash),
            nonce_block
        );
        DataProof storage proof = _publicDataProofs[proofKey];

        require(proof.proofBlockHeight > 0, "proof not exist");
        require(
            block.number - proof.proofBlockHeight > sysConfig.showTimeout,
            "proof not unlock"
        );

        if (block.number - proof.proofBlockHeight > sysConfig.showTimeout) {
            //Last Show Proof successed! 获得奖励+增加积分
            PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
            _onProofSuccess(proof, publicDataInfo, dataMixedHash);

            //防止重入：反复领取奖励
            proof.proofBlockHeight = 0;
        }
    }

    /**
     * @dev Show data proof, the data is registerd in the public data contract
     * @param dataMixedHash The mix_hash of the data
     * @param nonce_block The block height of the random number NONCE of this show, the height of this block must be less than the current block height, and within the appropriate time range
     * @param index proof.index
     * @param m_path proof.merkle_path of
     * @param leafdata proof.leaf_data
     * @param showType The type of the show：Immediately or Normal. The immediately mode needs to lock more pledged coins, but it can be understood that the reward is rewarded. The Normal model does not need to lock so many pledged coins, but it needs to be rewarded after the storage challenge is expired.
     *                 On the network with a high handling fee, we recommend using the right mode immediately. On the network with a lower handling fee, we recommend using the NORMAL mode
     */
    function showData(
        bytes32 dataMixedHash,
        uint256 nonce_block,
        uint32 index,
        bytes16[] calldata m_path,
        bytes calldata leafdata,
        ShowType showType
    ) public {
        uint256 proofKey = _mergeMixHashAndHeight(
            uint256(dataMixedHash),
            nonce_block
        );
        DataProof storage proof = _publicDataProofs[proofKey];

        bool isNewShow = false;
        address supplier = msg.sender;

        if (proof.proofBlockHeight == 0) {
            require(
                block.number - nonce_block <= sysConfig.maxNonceBlockDistance,
                "invalid nonce block"
            );
            isNewShow = true;
        } else {
            require(
                block.number - proof.proofBlockHeight <= sysConfig.showTimeout,
                "challenge timeout"
            );
        }

        (bytes32 root_hash, ) = _verifyDataProof(
            dataMixedHash,
            nonce_block,
            index,
            m_path,
            leafdata
        );

        if (isNewShow) {
            //Decide The Amount According To ShowType
            PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
            (uint256 lockAmount, bool isImmediately) = _LockSupplierPledge(
                supplier,
                dataMixedHash,
                showType
            );

            proof.lockedAmount = lockAmount;
            proof.nonceBlockHeight = nonce_block;
            proof.proofResult = root_hash;
            proof.proofBlockHeight = block.number;
            proof.prover = msg.sender;
            //proof.showType = showType;

            if (isImmediately) {
                _onProofSuccess(proof, publicDataInfo, dataMixedHash);
            }
        } else {
            // There is already a challenge to exist: judging whether the result is better, if better, update the results, and update the block height
            if (root_hash < proof.proofResult) {
                _supplierInfos[proof.prover].lockedBalance -= proof
                    .lockedAmount;

                uint256 rewardFromPunish = (proof.lockedAmount * 8) / 10;
                gwtToken.transfer(msg.sender, rewardFromPunish);
                gwtToken.transfer(
                    foundationAddress,
                    proof.lockedAmount - rewardFromPunish
                );

                emit SupplierPunished(
                    proof.prover,
                    dataMixedHash,
                    proof.lockedAmount
                );
                emit SupplierBalanceChanged(
                    proof.prover,
                    _supplierInfos[proof.prover].avalibleBalance,
                    _supplierInfos[proof.prover].lockedBalance
                );

                //Decide The Amount According To ShowType
                PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
                (uint256 lockAmount, bool isImmediately) = _LockSupplierPledge(
                    supplier,
                    dataMixedHash,
                    showType
                );

                if (isImmediately) {
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

    function _getDataOwner(
        bytes32 dataMixedHash,
        PublicData storage publicDataInfo
    ) internal view returns (address) {
        return
            IERCPublicDataContract(publicDataInfo.dataContract).getDataOwner(
                dataMixedHash
            );
    }

    /**
     * @dev Withdraw the reward of the data at special cycle, the reward is calculated according to the ranking of the data in the current cycle
     * @param cycleNumber The cycle number
     * @param dataMixedHash The mix_hash of the data
     */
    function withdrawReward(uint256 cycleNumber, bytes32 dataMixedHash) public {
        // Judging that the cycle of this time has ended
        //require(_currectCycle > cycleNumber, "cycle not finish");
        require(
            block.number > cycleNumber * sysConfig.blocksPerCycle + _startBlock,
            "cycle not finish"
        );
        CycleInfo storage cycleInfo = _cycleInfos[cycleNumber];
        CycleDataInfo storage dataInfo = cycleInfo.dataInfos[dataMixedHash];
        //REVIEW:The cost of GAS and 32 memory sorting in one time?
        uint256 scoreListRanking = cycleInfo.scoreList.getRanking(
            dataMixedHash
        );
        require(scoreListRanking > 0, "data not in rank");

        // No matter who take it, extract all the rewards at one time, and update the points
        require(dataInfo.score > 0, "already withdraw");

        // How many rewards to calculate
        uint256 totalReward = (cycleInfo.totalAward * 8) / 10;

        uint8 score = _getRewardScore(scoreListRanking);
        // If the total amount of data is less than 32, so excess rewards are precipitated in the contract account
        uint256 dataReward = (totalReward * score) / totalRewardScore;


        // transfoer 20% to owner
        gwtToken.transfer(
            _getDataOwner(dataMixedHash, _publicDatas[dataMixedHash]),
            dataReward / 5
        );

        // transfoer 50% to sponser
        gwtToken.transfer(_publicDatas[dataMixedHash].sponsor, dataReward / 2);

        // last showers
        uint256 showerReward = (dataReward - dataReward / 2 - dataReward / 5) /
            dataInfo.lastShowers.length;
        for (uint8 i = 0; i < dataInfo.lastShowers.length; i++) {
            gwtToken.transfer(dataInfo.lastShowers[i], showerReward);
        }

        // Setting Reward Have Been Taken
        dataInfo.score = 0;

        // Update points
        emit DataPointAdded(dataMixedHash, score);
        emit WithdrawReward(dataMixedHash, cycleNumber);
    }
}
