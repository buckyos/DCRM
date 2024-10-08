// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./gwt.sol";
import "./sortedlist.sol";
import "./PublicDataProof.sol";
import "./dividend.sol";

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

    struct ShowRecord {
        uint256 showTime;
        uint256 showCycle;
    }

    struct PublicData {
        address sponsor;
        address dataContract;
        uint256 maxDeposit;
        uint256 dataBalance;
        uint64 pledgeRate;
        mapping(address => ShowRecord) show_records; //miner address - > last show time
    }

    struct PublicDataForOutput {
        address sponsor;
        address dataContract;
        uint256 maxDeposit;
        uint256 dataBalance;
        uint64 depositRatio;
    }

    struct DataProof {
        bytes32 nonceBlockHash;
        uint256 proofBlockTime;
        bytes32 proofResult;
        address prover;
        // ShowType showType;
        uint256 lockedAmount;
    } 

    struct SupplierInfo {
        uint256 avalibleBalance;
        uint256 lockedBalance;
        uint256 unlockTime;
        uint256 lastShowBlock;
        string supplierExtra;
    }

    GWT public gwtToken; // Gb per Week Token
    DividendContract public dividendContract;

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
        uint256 totalAward;         // Record the total reward of this Cycle
        uint256 totalShowPower;     //Record the support of this cycle
        uint256 cycleStartTime;
        uint256 cycleGrowthRate;    // from 5 to 10000, Thousandths
    }

    struct CycleOutputInfo {
        uint256 totalReward;
        bytes32[] dataRanking;
    }

    //cycel nunber => cycle info
    uint256 public currectCycle;
    mapping(uint256 => CycleInfo) _cycleInfos;

    struct SysConfig {
        uint32 minPledgeRate;
        uint32 minPublicDataStorageWeeks;
        uint32 minLockWeeks;
        uint32 cycleMinTime;
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
   
    event DataPointAdded(bytes32 indexed mixedHash, uint64 point);
    event SupplierReward(address indexed supplier, bytes32 indexed mixedHash, uint256 amount);
    event SupplierPunished(address indexed supplier, bytes32 indexed mixedHash, uint256 amount);
    event ShowDataProof(
        address indexed supplier,
        bytes32 indexed dataMixedHash,
        uint256 nonce_block
    );
    event WithdrawReward(bytes32 indexed mixedHash, uint256 indexed cycle);
    event CycleStart(uint256 cycleNumber, uint256 startReward);
    event ChallengeFail(address indexed prover, bytes32 indexed dataMixedHash, uint256 nonce_block);

    function initialize(
        address _gwtToken,
        address _dividendContract
    ) public initializer {
        __PublicDataStorageUpgradable_init(_gwtToken, _dividendContract);
    }

    function __PublicDataStorageUpgradable_init(
        address _gwtToken,
        address _dividendContract
    ) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);

        gwtToken = GWT(_gwtToken);
        currectCycle = 2;   // Start from cycle 2. Cycle 0 and 1 treats as initial cycle, its power should be 0;
        dividendContract = DividendContract(payable(_dividendContract));
        totalRewardScore = 1600;

        sysConfig.minPledgeRate = 16; // Create data is the minimum of 16 times
        sysConfig.minPublicDataStorageWeeks = 96; //Create data is the minimum of 96 weeks
        sysConfig.minLockWeeks = 24; // The minimum is 24 weeks when it is at the current fixed value
        sysConfig.cycleMinTime = 259200; // Each cycle is 72 hours
        sysConfig.topRewards = 32; // TOP 32 entry list
        sysConfig.lockAfterShow = 172800; // You can unlock it within 48 hours after show
        sysConfig.showTimeout = 14400; // 4 hours after show, allow challenges
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
            240, 180, 150, 120, 100, 80, 60, 53, 
            42, 36, 35, 34, 33, 32, 31, 30, 
            29, 28, 27, 26, 25, 24, 23, 22, 
            21, 20, 19, 18, 17, 16, 15, 14
        ];
        if (ranking <= rewardScores.length) {
            return rewardScores[ranking - 1];
        } else {
            return 0;
        }
    }

    function _getRemainScore(uint256 length) internal pure returns (uint16) {
        uint16[33] memory remainScores = [
            1600, 1360, 1180, 1030, 910, 810, 730,
            670, 617, 575, 539, 504, 470, 437, 405,
            374, 344, 315, 287, 260, 234, 209, 185,
            162, 140, 119, 99, 80, 62, 45, 29, 14, 0
        ];

        return remainScores[length];
    }

    // By recording a final cycle, there may be empty cycle problems between cycles
    function _ensureCurrentCycleStart() internal returns (CycleInfo storage) {
        CycleInfo storage curCycleInfo = _cycleInfos[currectCycle];
        // If currect cycle lasts enough time, it should start a new cycle
        // Start a cycle: 20% from the reward of the previous cycle
        if (block.timestamp - curCycleInfo.cycleStartTime > sysConfig.cycleMinTime) {
            uint256 lastCycleReward = curCycleInfo.totalAward;
            // 5% as a foundation income
            uint256 fundationIncome = (lastCycleReward * 5) / 100;
            
            // deposit fundation income to dividend contract
            gwtToken.approve(address(dividendContract), fundationIncome);
            dividendContract.deposit(fundationIncome, address(gwtToken));

            // If the last round of the award -winning data is less than 32, the remaining bonuses are also rolled into this round prize pool
            uint16 remainScore = _getRemainScore(curCycleInfo.scoreList.length());
            uint256 remainReward = (lastCycleReward * 4 * remainScore) / totalRewardScore / 5;

            // Calculate the GrowthRate of this cycle when the cycle ends
            uint256 last_power = _cycleInfos[currectCycle - 1].totalShowPower;
            if (last_power > 0 && curCycleInfo.totalShowPower > last_power*1005/1000) {
                uint256 growth_rate = (curCycleInfo.totalShowPower - last_power) * 1000 / last_power;
                if (growth_rate > 10000) {
                    growth_rate = 10000;
                }

                curCycleInfo.cycleGrowthRate = growth_rate;
            } else {
                curCycleInfo.cycleGrowthRate = 5;
            }

            // move to next cycle
            currectCycle += 1;
            _cycleInfos[currectCycle].cycleStartTime = block.timestamp;
            _cycleInfos[currectCycle].totalAward = lastCycleReward - ((lastCycleReward * 4) / 5) - fundationIncome + remainReward;

            emit CycleStart(currectCycle, _cycleInfos[currectCycle].totalAward);
        }

        return _cycleInfos[currectCycle];
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

    function minCreateDepositAmount(uint64 dataSize, uint64 pledgeRate) public view returns (uint256) {
        return pledgeRate * _dataSizeToGWT(dataSize) * sysConfig.minPublicDataStorageWeeks * sysConfig.createDepositRatio;
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
        uint256 minAmount = minCreateDepositAmount(dataSize, pledgeRate);
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
            _cycleInfos[currectCycle].dataInfos[dataMixedHash].lastShowers;
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

    function getSupplierInfo(
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

    function setSupplierExtra(string calldata extra) public {
        SupplierInfo storage supplierInfo = _supplierInfos[msg.sender];
        require(supplierInfo.avalibleBalance + supplierInfo.lockedBalance > 0, "MUST pledge first");
        supplierInfo.supplierExtra = extra;
    }

    function getSupplierExtra(address supplier) public view returns (string memory) {
        return _supplierInfos[supplier].supplierExtra;
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
        if (supplierInfo.unlockTime < block.timestamp) {
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

    function getLockAmount(uint64 dataSize, ShowType showType, uint64 pledgeRate, uint256 dataBalance) public view returns (uint256) {
        uint256 normalLockAmount = _dataSizeToGWT(dataSize) * pledgeRate * sysConfig.minLockWeeks;
        if(showType == ShowType.Immediately) {
            uint256 immediatelyLockAmount = (dataBalance * 2) / 10;
            immediatelyLockAmount < sysConfig.minImmediatelyLockAmount ? sysConfig.minImmediatelyLockAmount : immediatelyLockAmount;
            return normalLockAmount + immediatelyLockAmount;
        } else {
            return normalLockAmount;
        }
    }

    function _getLockAmountByHash(
        bytes32 dataMixedHash,
        ShowType showType
    ) internal view returns (uint256) {
        uint64 dataSize = PublicDataProof.lengthFromMixedHash(dataMixedHash);
        return getLockAmount(dataSize, showType, _publicDatas[dataMixedHash].pledgeRate, _publicDatas[dataMixedHash].dataBalance);
    }

    function _LockSupplierPledge(
        address supplierAddress,
        bytes32 dataMixedHash,
        ShowType showType
    ) internal returns (uint256) {
        _adjustSupplierBalance(supplierAddress);

        SupplierInfo storage supplierInfo = _supplierInfos[supplierAddress];

        uint256 lockAmount = _getLockAmountByHash(dataMixedHash, showType);

        require(
            supplierInfo.avalibleBalance >= lockAmount,
            "insufficient balance"
        );
        supplierInfo.avalibleBalance -= lockAmount;
        supplierInfo.lockedBalance += lockAmount;
        supplierInfo.unlockTime = block.timestamp + sysConfig.lockAfterShow;
        emit SupplierBalanceChanged(
            supplierAddress,
            supplierInfo.avalibleBalance,
            supplierInfo.lockedBalance
        );
        return lockAmount;
    }

    function _verifyDataProof(
        bytes32 dataMixedHash,
        bytes32 nonce,
        uint32 index,
        bytes16[] calldata m_path,
        bytes calldata leafdata
    ) private view returns (bytes32, bytes32) {
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
            // if size less than 1GB, we treat it as 1 score
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

    // growth_rate is thousandths, 5-10000
    // also return thousandths.
    function _getGWTDifficultRatio(uint256 total_size, uint256 growth_rate) public pure returns (uint256) {
        // This function is essentially, the weekly interest rate is returned
        // 1) Calculate the basic difficulty values ​​according to the total power. Each time the computing power doubles, the basic difficulty value will decrease from <= 1pb, 2pb, 4pb, 8pb, 16pb, 32pb, 64pb, 128pb, 256pb, 512pb ..Adjust the foundation difficulty
        // The multiplier result is 8X -1X. When the total power is 1PB (GWT), the multiplier rate is 8X, and the computing power then doubles, and the magnification decreases by 10%.Multiple rate = 0.9^(log2 (support/1pb)), double the total power each time, the multiplier is 90%
        // After the difficulty adjustment of about 21 times, it will become 1x. At this time, the system capacity is already 1pb * 2^21 = 2EB
        // 2) Calculate the benchmark GWT interest rate (increasing speed) according to the computing power growth X, y = f (x), and the value domain of x is from [0, positive infinity] y to be the minimum value of 0.2%, the maximum, the maximum, the maximum, the maximum, the maximumValue is 2%

        // According to the above rules, the largest GWT mining ratio is the largest, 16%of the total mortgage (16%of the weekly return).That is, the miners pledged 100 GWTs in public data mining. After 1 week, they could dig out 16 GWT, which is close to 6.25 weeks.
        // If the total computing power is low in the early days, but no one digs it, the weekly return is 1.6%(1.6%of the weekly return), that is, the miners pledged 100 GWTs in public data mining.1.6 GWT, close to 62.5 weeks back       
            
        // m = 1024*1024 - 1024*8*growth_rate
        // result = (0.243*m) / (total_size+0.867*m) + 0.02
        uint256 m = 1024 * (1024*10000 - 8*growth_rate);
        return (243*m)*1000 / (total_size*1000 + 867*m) + 20;
    }

    function _onProofSuccess(
        DataProof storage proof,
        PublicData storage publicDataInfo,
        bytes32 dataMixedHash,
        address challengeAddr
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

        // if not challenge, update the score
        if (challengeAddr == address(0)) {
            //Increase according to the proportion of file size ， 0.1G - 1G 1，1G-4G 2， 4G-8G 3，8G-16G 4 16G-32G 5 ...
            uint64 score = _scoreFromHash(dataMixedHash);
            dataInfo.score += score;
            
            emit DataPointAdded(dataMixedHash, score);

            //Only exceeding the threshold will update the ranking. This setting will cause the user to be dissatisfied when there are not many users (forced cumulative bonuses)
            if (dataInfo.score > sysConfig.minRankingScore) {
                if (cycleInfo.scoreList.maxlen() < sysConfig.topRewards) {
                    cycleInfo.scoreList.setMaxLen(sysConfig.topRewards);
                }
                cycleInfo.scoreList.updateScore(dataMixedHash, dataInfo.score);
            }
        }

        // Update Cycle's Last Shower
        _updateLastSupplier(dataInfo, challengeAddr, msg.sender);
        
        ShowRecord storage lastShowRecord = publicDataInfo.show_records[msg.sender];
        if (lastShowRecord.showTime == 0) {
            publicDataInfo.show_records[msg.sender] = ShowRecord(block.timestamp, currectCycle);
        } else {
            //The second SHOW! Get GWT mining award
            uint256 showDeltaTime = block.timestamp - lastShowRecord.showTime;
            if (showDeltaTime > 1 weeks) {
                // calcute the valid storage power
                // reward = size * T * pledgeRate * difficultRatio
                // T = currect time - last show time, T must be greater than 1 week, up to 4 weeks
                publicDataInfo.show_records[msg.sender] = ShowRecord(block.timestamp, currectCycle);
                uint256 storageWeeks = (showDeltaTime) / 1 weeks;
                if (storageWeeks > 8) {
                    storageWeeks = 8;
                }
                uint256 size = PublicDataProof.lengthFromMixedHash(dataMixedHash) >> 30;
                if (size == 0) {
                    // if size < 1GB, we treat it as 1GB
                    size = 1;
                }

                uint256 storagePower = size * storageWeeks * publicDataInfo.pledgeRate * 16;
                cycleInfo.totalShowPower += storagePower ;

                // the difficult ratio is calculated by the total power of the current cycle and the total power of the last cycle
                CycleInfo storage lastShowCycle = _cycleInfos[lastShowRecord.showCycle];
                CycleInfo storage curCycle = _cycleInfos[currectCycle - 1];
                uint256 avgShowPower = (lastShowCycle.totalShowPower + curCycle.totalShowPower) / 2;
                uint256 avgGrowthRate = (lastShowCycle.cycleGrowthRate + curCycle.cycleGrowthRate) / 2;
                // _getGWTDifficultRatio return thousandths
                uint256 gwtReward = storagePower * _getGWTDifficultRatio(avgShowPower, avgGrowthRate) * (10 ** 18) / 1000;

                // 80% of the reward is given to the miner, and 20% is given to the current data balance
                gwtToken.mint(msg.sender, gwtReward * 8 / 10);
                
                gwtToken.mint(address(this), gwtReward * 2 / 10);
                publicDataInfo.dataBalance += gwtReward * 2 / 10;
            }
        }

        // prevent reentry: repeatedly receive rewards
        proof.proofBlockTime = 0;
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

        require(proof.proofBlockTime > 0, "proof not exist or already withdrawed");
        require(
            block.timestamp - proof.proofBlockTime > sysConfig.showTimeout,
            "proof not unlock"
        );

        // Finally Show Proof successed! Get Show Rewards
        PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
        _onProofSuccess(proof, publicDataInfo, dataMixedHash, address(0));
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

        if (proof.prover == address(0)) {
            // a new proof, check params
            require(
                block.number - nonce_block <= sysConfig.maxNonceBlockDistance,
                "input nonce block too old"
            );
            require(nonce_block < block.number, "nonce_block too high");
            require(block.number - nonce_block < 256, "nonce block too old");

            proof.nonceBlockHash = blockhash(nonce_block);
        } else {
            // challenge exist proof
            // if proof not exist, proof.proofBlockTime = 0, block.timestamp always less then sysConfig.showTimeout
            require(block.timestamp - proof.proofBlockTime <= sysConfig.showTimeout, "challenge timeout");
        }

        (bytes32 root_hash, ) = _verifyDataProof(
            dataMixedHash,
            proof.nonceBlockHash,
            index,
            m_path,
            leafdata
        );

        if (proof.prover != address(0)) {
            if (root_hash < proof.proofResult) {
                // challenge success!
                _supplierInfos[proof.prover].lockedBalance -= proof.lockedAmount;

                // send 80% punish income to challenger
                uint256 rewardFromPunish = (proof.lockedAmount * 8) / 10;
                gwtToken.transfer(msg.sender, rewardFromPunish);

                // deposit 20% punish income to dividend contract
                gwtToken.approve(address(dividendContract), proof.lockedAmount - rewardFromPunish);
                dividendContract.deposit(proof.lockedAmount - rewardFromPunish, address(gwtToken));

                emit SupplierPunished(proof.prover, dataMixedHash, proof.lockedAmount);
                emit SupplierBalanceChanged(proof.prover,
                    _supplierInfos[proof.prover].avalibleBalance,
                    _supplierInfos[proof.prover].lockedBalance
                );
            } else {
                // challenge failed!
                emit ChallengeFail(msg.sender, dataMixedHash, nonce_block);
                return;
            }
        }

        // lock supplier pledge
        // Decide The Amount According To ShowType
        PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
        uint256 lockAmount = _LockSupplierPledge(msg.sender,dataMixedHash,showType);

        if (showType == ShowType.Immediately) {
            _onProofSuccess(proof, publicDataInfo, dataMixedHash, proof.prover);
        }

        proof.lockedAmount = lockAmount;
        proof.proofResult = root_hash;
        proof.proofBlockTime = block.timestamp;
        proof.prover = msg.sender;

        emit ShowDataProof(msg.sender, dataMixedHash, nonce_block);
    }

    function _getDataOwner(
        bytes32 dataMixedHash,
        PublicData storage publicDataInfo
    ) internal view returns (address) {
        return IERCPublicDataContract(publicDataInfo.dataContract).getDataOwner(dataMixedHash);
    }

    /**
     * @dev Withdraw the reward of the data at special cycle, the reward is calculated according to the ranking of the data in the current cycle
     * @param cycleNumber The cycle number
     * @param dataMixedHash The mix_hash of the data
     */
    function withdrawReward(uint256 cycleNumber, bytes32 dataMixedHash) public {
        // Judging that the cycle of this time has ended
        require(currectCycle > cycleNumber, "cycle not finish");
        CycleInfo storage cycleInfo = _cycleInfos[cycleNumber];
        CycleDataInfo storage dataInfo = cycleInfo.dataInfos[dataMixedHash];
        //REVIEW:The cost of GAS and 32 memory sorting in one time?
        uint256 scoreListRanking = cycleInfo.scoreList.getRanking(dataMixedHash);
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
