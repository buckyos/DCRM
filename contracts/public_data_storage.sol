// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERCPublicDataContract {
    //return the owner of the data
    function getDataOwner(bytes32 dataHash) public view returns (address);

    //return token data hash
    function tokenDataHash(uint256 _tokenId) external view returns (bytes32);
}

contract PublicDataStorage {
    struct PublicData {
        bytes32 mixedHash;
        address owner;
        address sponsor;
        uint256 maxDeposit;
        uint256 score;
    }

    mapping(bytes32 => PublicData) public_datas;
    uint256 system_reward_pool;
    mapping(bytes32 => uint256) data_balance;
    mapping(uint256 => mapping(uint256 => bool)) all_shows;

    function getDataSize(bytes32 dataHash) public pure returns (uint64) {
        return uint64(dataHash >> 192);
    }

    function _verifyData(
        uint supplierId,
        bytes32 dataMixedHash,
        bytes32 blockHash
    ) internal returns(bool) {
        // TODO
        return true;
    }

    function createPublicData(
        bytes32 dataMixedHash,
        uint64 depositRatio,
        address publicDataContract,
        uint256 tokenId
    ) public {
        PublicData memory publicDataInfo = new PublicData(dataMixedHash);
        publicDataInfo.sponsor = msg.sender;
        if (publicDataContract == address(0)) {
            publicDataInfo.owner = msg.sender;
        } else if (tokenId == 0) {
            // token id must be greater than 0
            publicDataInfo.owner = publicDataContract.owner();
        } else {
            // if provided token id, then dataMixedHash will be ignored
            require(
                dataMixedHash ==
                    IERCPublicDataContract(publicDataContract).tokenDataHash(
                        tokenId
                    )
            );
            publicDataInfo.owner = IERCPublicDataContract(publicDataContract)
                .getDataOwner(publicDataInfo.hash);
        }

        // transfer deposit
        require(depositRatio >= 48);

        // get data size from data hash
        uint64 dataSize = getDataSize(publicDataInfo.hash);
        uint256 depositAmount = (depositRatio * dataSize * 10 ** 18) >> 30;

        publicDataInfo.maxDeposit = depositAmount;

        gwtToken.transferFrom(msg.sender, address(this), depositAmount);
        data_balance[publicDataInfo.hash] += (depositAmount * 8) / 10;
        system_reward_pool += depositAmount - ((depositAmount * 8) / 10);

        public_datas[dataMixedHash] = publicDataInfo;
    }

    function addDeposit(bytes32 dataMixedHash, uint64 depositRatio) public {
        PublicData storage publicDataInfo = public_datas[dataMixedHash];
        require(publicDataInfo.hash != 0);
        require(publicDataInfo.owner == msg.sender);

        // transfer deposit
        require(depositRatio >= 48);

        // get data size from data hash
        uint64 dataSize = getDataSize(publicDataInfo.hash);
        uint256 depositAmount = (depositRatio * dataSize * 10 ** 18) >> 30;

        gwtToken.transferFrom(msg.sender, address(this), depositAmount);
        data_balance[publicDataInfo.hash] += (depositAmount * 8) / 10;
        system_reward_pool += depositAmount - ((depositAmount * 8) / 10);

        if (depositAmount > ((publicDataInfo.maxDeposit * 11) / 10)) {
            publicDataInfo.sponsor = msg.sender;
        }

        if (depositAmount > publicDataInfo.maxDeposit) {
            publicDataInfo.maxDeposit = depositAmount;
        }
    }

    function _validPublicSupplier(uint supplierId, bytes32 dataMixedHash) internal view returns(bool) {
        // TODO: How to ensure the supplier has centern remaining space? GWT TOken?
        // return gwtToken.balanceOf(all_supplier[supplierId].cfo) > 16 * 10 ** 18 * getDataSize(dataMixedHash));
        return true;
    }

    function showData(uint supplierId, bytes32 dataMixedHash) public {
        require(_validPublicSupplier(supplierId, dataMixedHash));
        require(all_supplier[supplierId].cfo == msg.sender);
        require(all_shows[block.number][supplierId] == false);

        // check block.number meets certain conditions
        require(_verifyData(supplierId, dataMixedHash, blockhash(block.number - 1)));

        PublicData storage publicDataInfo = public_datas[dataMixedHash];

        // TODO: how to calcute score according to data size?
        publicDataInfo.score += getDataSize(publicDataInfo.mixedHash);

        // There may be some predicated logic here that is beneficial to optimize the sorting
        
        all_shows[block.number][supplierId] = true;
    }
}
