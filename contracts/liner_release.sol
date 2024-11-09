// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract LinerRelease is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    struct LockupInfo {
        address to;
        address tokenAddr;
        uint256 amount;
        uint256 firstReleaseTime;
        uint256 finalReleaseTime;
        uint256 firstReleaseAmount;
        uint256 releasedAmount;
    }
    mapping(uint256 => LockupInfo) public lockupInfos;
    uint256 public lockupId;

    event StartLockUp(uint256 lockupId, address indexed to);
    event Withdraw(uint256 lockupId, address indexed to, uint256 amount);

    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        lockupId = 0;
    }

    function startLock(IERC20 tokenAddr, uint256 amount, address to, uint256 firstReleaseDuration, uint256 firstReleaseAmount, uint256 finalReleaseDuration) public {
        require(finalReleaseDuration >= firstReleaseDuration, "invalid duration");
        tokenAddr.transferFrom(msg.sender, address(this), amount);
        lockupInfos[++lockupId] = LockupInfo(to, address(tokenAddr), amount, block.timestamp + firstReleaseDuration, block.timestamp + finalReleaseDuration, firstReleaseAmount, 0);

        emit StartLockUp(lockupId, to);
    }

    function withdraw(uint256 lockupId) public {
        LockupInfo storage lockupInfo = lockupInfos[lockupId];
        require(lockupInfo.to == msg.sender, "invalid receiver");
        require(block.timestamp >= lockupInfo.firstReleaseTime, "not time");

        // 计算应该释放的数量
        uint256 amount = lockupInfo.firstReleaseAmount;
        uint256 releaseTime = block.timestamp;
        if (block.timestamp > lockupInfo.finalReleaseTime) {
            releaseTime = lockupInfo.finalReleaseTime;
        }
        amount += (lockupInfo.amount - lockupInfo.firstReleaseAmount) * (releaseTime - lockupInfo.firstReleaseTime) / (lockupInfo.finalReleaseTime - lockupInfo.firstReleaseTime);
        
        IERC20(lockupInfo.tokenAddr).transfer(lockupInfo.to, amount - lockupInfo.releasedAmount);
        emit Withdraw(lockupId, lockupInfo.to, amount - lockupInfo.releasedAmount);
        lockupInfo.releasedAmount = amount;
    }

    function canWithdraw(uint256 lockupId) public view returns (uint256) {
        LockupInfo storage lockupInfo = lockupInfos[lockupId];
        if (lockupInfo.to != msg.sender) {
            console.log("not receiver");
            return 0;
        }
        if (block.timestamp < lockupInfo.firstReleaseTime) {
            console.log("cur %d, first %d", block.timestamp, lockupInfo.firstReleaseTime);
            return 0;
        }

        uint256 amount = lockupInfo.firstReleaseAmount;
        uint256 releaseTime = block.timestamp;
        if (block.timestamp > lockupInfo.finalReleaseTime) {
            releaseTime = lockupInfo.finalReleaseTime;
        }
        amount += (lockupInfo.amount - lockupInfo.firstReleaseAmount) * (releaseTime - lockupInfo.firstReleaseTime) / (lockupInfo.finalReleaseTime - lockupInfo.firstReleaseTime);
        return amount - lockupInfo.releasedAmount;
    }

    function lockupInfo(uint256 lockupId) public view returns (LockupInfo memory) {
        return lockupInfos[lockupId];
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}