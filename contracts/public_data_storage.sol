// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./gwt.sol";
import "./sortedlist.sol";
import "./PublicDataProof.sol";

import "hardhat/console.sol";

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
    enum ShowType { Normal, Immediately }
    struct PublicData {
        address owner;
        address sponsor;
        address nftContract;
        uint256 tokenId;
        uint256 depositRatio;
        uint256 maxDeposit;
        uint256 dataBalance;
        uint64 point;
    }

    struct DataProof {
        uint256 nonceBlockHeight;
        uint256 proofBlockHeight;
        bytes32 proofResult;
        address prover;
        ShowType showType;
        uint256 lockedAmount;
    }

    struct SupplierInfo {
        uint256 avalibleBalance;
        uint256 lockedBalance;
        uint256 unlockBlock;
        uint256 lastShowBlock;
    }

    GWTToken public gwtToken;// Gb per Week Token
    address public foundationAddress;

    mapping(address => SupplierInfo) _supplierInfos;
    mapping(bytes32 => PublicData) _publicDatas;
    mapping(uint256 => DataProof) _publicDataProofs;

    struct CycleDataInfo {
        address[5] lastShowers;
        uint64 score;//REVIEW uint64足够了？
        uint8 showerIndex;
        uint8 withdrawStatus;
    }

    struct CycleInfo {
        //Review：没必要每个Cycle都保存吧？可以合并到PublicData里，
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

    // 合约常量参数
    uint256 sysMinDepositRatio = 64;
    uint256 sysMinPublicDataStorageWeeks = 96;
    uint256 sysMinLockWeeks = 24;

    uint256 constant public blocksPerCycle = 17280;
    uint256 constant public topRewards = 32;
    uint256 constant public sysLockAfterShow = 11520;    // REVIEW 成功的SHOW 48小时之后才能提现
    uint256 constant public sysConfigShowTimeout = 5760; // REVIEW SHOW成功24小时之内允许挑战
    uint256 constant public syxMaxNonceBlockDistance = 2;  // 允许的nonce block距离, lockAfterShow + maxNonceBlockDistance要小于256
    //uint256 constant public difficulty = 4;   // POW难度，最后N个bit为0
    //uint256 constant public showDepositRatio = 3; // SHOW的时候抵押的GWT倍数
    //uint256 constant public totalRewardScore = 1572; // 将rewardScores相加得到的结果
    uint256 constant public totalRewardScore = 1600; // 将rewardScores相加得到的结果
    uint64 constant public sysMinDataSize = 1 << 27; // dataSize换算GWT时，最小值为128M

    event SupplierBalanceChanged(address supplier, uint256 avalibleBalance, uint256 lockedBalance);
    event GWTStacked(address supplier, uint256 amount);
    event GWTUnstacked(address supplier, uint256 amount);
    event PublicDataCreated(bytes32 mixedHash);
    event DepositData(address depositer, bytes32 mixedHash, uint256 balance, uint256 reward);
    event SponsorChanged(bytes32 mixedHash, address oldSponsor, address newSponsor);
    event SupplierReward(address supplier, bytes32 mixedHash, uint256 amount);
    event SupplierPubished(address supplier, bytes32 mixedHash, uint256 amount);
    event ShowDataProof(address supplier, bytes32 dataMixedHash);
    event WithdrawAward(bytes32 mixedHash, address user, uint256 amount);

    constructor(address _gwtToken, address _Foundation) {
        gwtToken = GWTToken(_gwtToken);
        _startBlock = block.number;
        _currectCycle = 0;
        _minRankingScore = 64;
        foundationAddress = _Foundation;
    }

    function _getRewardScore(uint256 ranking) internal pure returns(uint256) {
        /*
        uint8[32] memory rewardScores = [
            240, 180, 150, 120, 100, 80, 60, 50, 40, 
            35, 34, 33, 32, 31, 30, 29, 28, 27, 26, 25, 
            24, 23, 22, 21, 20, 19, 18 ,17, 16, 15, 14, 13
        ];
        */
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

    function _verifyBlockNumber(bytes32 dataMixedHash, uint256 blockNumber) internal pure returns(bool) {
        // (blockNumber xor dataMixedHash) % 64 == 0
        return uint256(bytes32(blockNumber) ^ dataMixedHash) % 64 == 0;
    }

    function _cycleNumber() internal view returns(uint256) {
        uint cycleNumber = (block.number - _startBlock) / blocksPerCycle;
        if (cycleNumber * blocksPerCycle + _startBlock < block.number) {
            cycleNumber += 1;
        }
        return cycleNumber;
    }

    // 通过记录一个最后的周期来解决周期之间可能有空洞的问题
    function _addCycleReward(uint256 amount) private {
        uint256 cycleNumber = _cycleNumber();
        CycleInfo storage cycleInfo = _cycleInfos[cycleNumber];
        if (cycleInfo.totalAward == 0) {
            uint256 lastCycleReward = _cycleInfos[_currectCycle].totalAward;
            cycleInfo.totalAward = (lastCycleReward - (lastCycleReward * 4 / 5));
             _currectCycle = cycleNumber;
        }
        cycleInfo.totalAward += amount;
    }

    // 计算这些空间对应多少GWT，单位是wei
    // 不满128MB的按照128MB计算
    function _dataSizeToGWT(uint64 dataSize) internal pure returns(uint256) {
        uint64 fixedDataSize = dataSize;
        if (fixedDataSize < sysMinDataSize) {
            fixedDataSize = sysMinDataSize;
        }
        return (uint256(fixedDataSize) * 10 ** 18) >> 30;
    }

    function createPublicData(
        bytes32 dataMixedHash,
        uint64 depositRatio,
        uint256 depositAmount, 
        address publicDataContract,
        uint256 tokenId
    ) public {
        // 质押率影响用户SHOW数据所需要冻结的质押
        require(depositRatio >= sysMinDepositRatio, "deposit ratio is too small");
        require(dataMixedHash != bytes32(0), "data hash is empty");
        // minAmount = 数据大小*GWT兑换比例*最小时长*质押率
        // get data size from data hash
        uint64 dataSize = PublicDataProof.lengthFromMixedHash(dataMixedHash);
        uint256 minAmount = depositRatio * _dataSizeToGWT(dataSize) * sysMinPublicDataStorageWeeks;
        require(depositAmount >= minAmount, "deposit amount is too small");
        
        PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
        require(publicDataInfo.maxDeposit == 0, "public data already exists");

        publicDataInfo.depositRatio = depositRatio;
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
            require(dataMixedHash == IERC721VerfiyDataHash(publicDataContract).tokenDataHash(tokenId), "NFT data hash mismatch");
            publicDataInfo.nftContract = publicDataContract;
            publicDataInfo.tokenId = tokenId;
        }

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

    function getCurrectLastShowed(bytes32 dataMixedHash) public view returns(address[5] memory) {
        return _cycleInfos[_cycleNumber()].dataInfos[dataMixedHash].lastShowers;
    }

    function getDataInCycle(uint256 cycleNumber, bytes32 dataMixedHash) public view returns(CycleDataInfo memory) {
        return _cycleInfos[cycleNumber].dataInfos[dataMixedHash];
    }

    function getCycleInfo(uint256 cycleNumber) public view returns(CycleOutputInfo memory) {
        return CycleOutputInfo(_cycleInfos[cycleNumber].totalAward, _cycleInfos[cycleNumber].scoreList.getSortedList());
    }

    function getOwner(bytes32 dataMixedHash) public view returns(address) {
        PublicData memory info = _publicDatas[dataMixedHash];
        if (info.owner != address(0)) {
            return info.owner;
        } else {
            return IERCPublicDataContract(info.nftContract).getDataOwner(dataMixedHash);
        }
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

    function _getLockAmountByHash(bytes32 dataMixedHash) internal view returns(uint256) {
        uint64 dataSize = PublicDataProof.lengthFromMixedHash(dataMixedHash);
        return _dataSizeToGWT(dataSize) * _publicDatas[dataMixedHash].depositRatio * sysMinLockWeeks;
    }

    function _LockSupplierPledge(address supplierAddress, bytes32 dataMixedHash, uint256 dataBlance) internal returns(uint256){
        _adjustSupplierBalance(supplierAddress);
        
        SupplierInfo storage supplierInfo = _supplierInfos[supplierAddress];
        
        uint256 lockAmount = _getLockAmountByHash(dataMixedHash);
        if(lockAmount < dataBlance) {
            lockAmount = dataBlance;
        }
        
        require(supplierInfo.avalibleBalance >= lockAmount, "insufficient balance");
        supplierInfo.avalibleBalance -= lockAmount;
        supplierInfo.lockedBalance += lockAmount;
        supplierInfo.unlockBlock = block.number + sysLockAfterShow;

        emit SupplierBalanceChanged(supplierAddress, supplierInfo.avalibleBalance, supplierInfo.lockedBalance);
        return lockAmount;
    }

    function _verifyDataProof(bytes32 dataMixedHash,uint256 nonce_block_high, uint32 index, bytes16[] calldata m_path, bytes calldata leafdata) private view returns(bytes32,bytes32) {
        require(nonce_block_high < block.number, "invalid nonce_block_high");
        require(block.number - nonce_block_high < 256, "nonce block too old");

        bytes32 nonce = blockhash(nonce_block_high);

        return PublicDataProof.calcDataProof(dataMixedHash, nonce, index, m_path, leafdata, bytes32(0));
    }

    function _mergeMixHashAndHeight(uint256 dataMixedHash, uint256 nonce_block) public pure returns (uint256) {
        uint256 highBits = dataMixedHash >> 64; 
        uint256 lowBits = nonce_block & ((1 << 64) - 1); 
        return (highBits << 64) | lowBits; 
    }

    function _onProofSuccess(DataProof storage proof,PublicData storage publicDataInfo,bytes32 dataMixedHash) private {
        
        uint256 reward = publicDataInfo.dataBalance / 10;
        // 当reward为0时，要不要增加积分？
        emit SupplierReward(proof.prover, dataMixedHash, reward);
        if (reward > 0) {
            //REVIEW 2:8分是在Sponsor里做的，正常胜利不用做
            // REVIEW：正常胜利没有抽成了么？考虑一个矿工有多个账户的情况，他可以自己show自己的数据，把create时抵押的GWT全部拿走。相当于无成本刷score
            // SHOW的收入来自数据的余额，这里已经被抽成20%了。
            gwtToken.transfer(proof.prover, reward);
            publicDataInfo.dataBalance -= reward;
        }

        //TODO:这里有机会开启新周期？要处理
        CycleInfo storage cycleInfo = _cycleInfos[_cycleNumber()];
        CycleDataInfo storage dataInfo = cycleInfo.dataInfos[dataMixedHash];
        // TODO：按文件大小的比例增加 ， 0.1G - 1G 1分，1G-4G 2分， 4G-8G 3分，8G-16G 4分 16G-32G 5分 ...  
        dataInfo.score += 1;
        publicDataInfo.point += 1;
        

        // insert supplier into last_showers
        if (dataInfo.showerIndex >= 5) {
            dataInfo.showerIndex = 0;
        }
        dataInfo.lastShowers[dataInfo.showerIndex] = proof.prover;
        dataInfo.showerIndex += 1;

        //只有超过阈值才会更新排名，这个设定会导致用户不多的时候排名不满（强制性累积奖金）
        if (dataInfo.score > _minRankingScore) {
            if (cycleInfo.scoreList.maxlen() < topRewards) {
                cycleInfo.scoreList.setMaxLen(topRewards);
            }
            cycleInfo.scoreList.updateScore(dataMixedHash, dataInfo.score);
        }
    }

    function showData(bytes32 dataMixedHash, uint256 nonce_block, uint32 index, bytes16[] calldata m_path, bytes calldata leafdata, ShowType showType) public {
        uint256 proofKey = _mergeMixHashAndHeight(uint256(dataMixedHash),nonce_block);
        DataProof storage proof = _publicDataProofs[proofKey];
        
        bool isNewShow = false;
        bool challengeSuccess = false;
        bool lastSuccess = false;
        address supplier = msg.sender;

        if(proof.proofBlockHeight == 0) {
            require(nonce_block < block.number && block.number - nonce_block <= syxMaxNonceBlockDistance, "invalid nonce block");
            isNewShow = true;
        } else {
            if (block.number - proof.proofBlockHeight > sysConfigShowTimeout) {
                //Last Show Proof successed! 获得奖励+增加积分
                PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
                _onProofSuccess(proof, publicDataInfo,dataMixedHash);
            
                //防止重入：反复领取奖励
                proof.proofBlockHeight = 0;
                return;
            }
            //在时间内，这是一个挑战
        }
    
        (bytes32 root_hash,) = _verifyDataProof(dataMixedHash,nonce_block,index,m_path,leafdata);
        address oldProver;

        if(isNewShow) {
            //根据showType决定锁定金额
            PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
            uint256 willLockAmount = 0;
            if(showType == ShowType.Immediately) {
                willLockAmount = publicDataInfo.dataBalance * 2 / 10;   
            } 
            proof.lockedAmount = _LockSupplierPledge(supplier, dataMixedHash,willLockAmount);
            if(willLockAmount !=0 && willLockAmount < proof.lockedAmount) {
               showType = ShowType.Normal;
            }
            proof.nonceBlockHeight = nonce_block;
            proof.proofResult = root_hash;
            proof.proofBlockHeight = block.number;
            proof.prover = msg.sender;
            proof.showType = showType;

            if(showType == ShowType.Immediately) {
                _onProofSuccess(proof, publicDataInfo, dataMixedHash);
            }

        } else {
            // 已经有挑战存在：判断是否结果更好，如果更好，更新结果，并更新区块高度
            if(root_hash < proof.proofResult) {
                
                _supplierInfos[proof.prover].lockedBalance -= proof.lockedAmount;

                uint256 awardFromPunish = proof.lockedAmount * 8 / 10;
                gwtToken.transfer(msg.sender, awardFromPunish);
                gwtToken.transfer(foundationAddress, proof.lockedAmount - awardFromPunish);
                

                oldProver = proof.prover;
                emit SupplierPubished(proof.prover, dataMixedHash, proof.lockedAmount);
                emit SupplierBalanceChanged(proof.prover, _supplierInfos[proof.prover].avalibleBalance, _supplierInfos[proof.prover].lockedBalance);

                PublicData storage publicDataInfo = _publicDatas[dataMixedHash];
                uint256 willLockAmount = 0;
                if(showType == ShowType.Immediately) {
                    willLockAmount = publicDataInfo.dataBalance * 2 / 10;   
                } 
                //TODO:这里锁定失败不应该回滚交易？
                // REVIEW：既然挑战者也走正常的show逻辑，也可以立刻拿到奖励，这里应该当作普通的supplier对待，否则他也是错的怎么办？
                proof.lockedAmount = _LockSupplierPledge(supplier, dataMixedHash,willLockAmount);
                if(willLockAmount !=0 && willLockAmount < proof.lockedAmount) {
                    showType = ShowType.Normal;
                }

                proof.proofResult = root_hash;
                proof.proofBlockHeight = block.number;
                proof.prover = msg.sender;
                proof.showType = showType;

                if(showType == ShowType.Immediately) {
                    _onProofSuccess(proof, publicDataInfo, dataMixedHash);
                }
            } 
        }
    }

    function _getDataOwner(bytes32 dataMixedHash, PublicData memory publicDataInfo) internal view returns(address) {
        if (publicDataInfo.owner != address(0)) {
            return publicDataInfo.owner;
        } else {
            return IERCPublicDataContract(publicDataInfo.nftContract).getDataOwner(dataMixedHash);
        }
    }

    // return: 1: sponsor, 2- 6: last shower, 7: owner, 0: no one
    function _getWithdrawRole(address sender, bytes32 dataMixedHash, PublicData memory publicDataInfo, CycleDataInfo memory dataInfo) internal view returns(uint8) {
        uint8 user = 0;
        if (sender == publicDataInfo.sponsor) {
            user |= 1 << 1;
        }

        if (sender == _getDataOwner(dataMixedHash, publicDataInfo)) {
            user |= 1 << 7;
        } 
    
        for (uint8 i = 0; i < dataInfo.lastShowers.length; i++) {
            if (dataInfo.lastShowers[i] == sender) {
                user |= uint8(1 << (i+2));
            }
        }

        return user;
    }

    // sponsor拿50%, owner拿20%, 5个last shower平分30%
    function _calcuteReward(uint8 user, uint256 totalReward, uint256 last_shower_length) internal pure returns(uint256) {
        uint reward = 0;
        if ((user >> 1) & 1 == 1) {
            reward += totalReward / 2;
        } 
        if ((user >> 7) & 1 == 1) {
            reward += totalReward / 5;
        }
        if (user & 124 > 0) {
            reward += (totalReward - totalReward / 2 - totalReward / 5) / last_shower_length;
        }

        return reward;
    }

    function withdrawAward(uint cycleNumber, bytes32 dataMixedHash) public {
        // 判断这次的cycle已经结束
        require(_currectCycle > cycleNumber, "cycle not finish");
        //require(block.number > cycleNumber * blocksPerCycle + _startBlock, "cycle not finish");
        CycleInfo storage cycleInfo = _cycleInfos[cycleNumber];
        CycleDataInfo storage dataInfo = cycleInfo.dataInfos[dataMixedHash];
        //REVIEW:一次排序并保存的GAS和32次内存排序的成本问题？
        uint256 scoreListRanking = cycleInfo.scoreList.getRanking(dataMixedHash);
        require(scoreListRanking > 0, "data not in rank");

        // 看看是谁来取
        uint8 withdrawUser = _getWithdrawRole(msg.sender, dataMixedHash, _publicDatas[dataMixedHash], dataInfo);

        require(withdrawUser > 0, "cannot withdraw");
        require(dataInfo.withdrawStatus & withdrawUser == 0, "already withdraw");

        // 计算该得到多少奖励
        uint256 totalReward = cycleInfo.totalAward * 8 / 10;

        uint256 data_score = _getRewardScore(scoreListRanking);
        // 如果数据总量不足32，那么多余的奖励沉淀在合约账户中
        // TODO：多余的奖励是不是可以让基金会提现？只沉淀在合约账户的话，最后要怎么办？
        uint256 dataReward = totalReward * data_score / totalRewardScore;
        uint256 reward = _calcuteReward(withdrawUser, dataReward, dataInfo.lastShowers.length);
        gwtToken.transfer(msg.sender, reward);
        
        // 设置已取标志
        dataInfo.withdrawStatus |= withdrawUser;

        emit WithdrawAward(dataMixedHash, msg.sender, reward);
    }
}
