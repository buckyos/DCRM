pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "hardhat/console.sol";

contract DividendContract is ReentrancyGuard {
    address public stakingToken;

    // the max length of the cycle in blocks
    uint256 public cycleMaxLength;
    
    // current cycle index, start at 0
    uint256 public currentCycleIndex;

    // the start block of the cycle of the contract
    uint256 public cycleStartBlock;

    struct RewardInfo {
        address token;
        uint256 amount;
    }

    struct CycleInfo {
        // The start block of the cycle
        uint256 startBlock;

        // the total stake amount of the curent cycle
        uint256 totalStaked;

        // the reward info of the cycle       
        RewardInfo[] rewards;
    }

    // the total staked amount of the contract of all users
    uint256 public totalStaked;

    // the cycle info of the contract
    //CycleInfo[] public cycles;
    mapping(uint256 => CycleInfo) public cycles;

    // the staking record of the user
    struct StakeRecord {
        uint256 cycleIndex;
        uint256 amount;
    }
     mapping(address => StakeRecord[]) UserStakeRecords;

    // the dividend state of the user
    mapping(bytes32 => bool) public withdrawDividendState;

    event Deposit(uint256 amount, address token);
    event Stake(address indexed user, uint256 amount);
    event Unstake(address indexed user, uint256 amount);
    event NewCycle(uint256 cycleIndex, uint256 startBlock);


    constructor(address _stakingToken, uint256 _cycleMaxLength) {
        stakingToken = _stakingToken;
        cycleMaxLength = _cycleMaxLength;
        cycleStartBlock = block.number;
    }

    function getCurrentCycleIndex() public view returns (uint256) {
        return currentCycleIndex;
    }

    function getCurrentCycle() public view returns (CycleInfo memory) {
        return cycles[currentCycleIndex];
    }

    // deposit token to the current cycle
    function _depositToken(address token, uint256 amount) internal {
        require(amount > 0, "Cannot deposit 0");

        RewardInfo[] storage rewards = cycles[currentCycleIndex].rewards;
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i].token == token) {
                rewards[i].amount += amount;
                return;
            }
        }

        rewards.push(RewardInfo(token, amount));

        emit Deposit(amount, token);
    }

    
    receive() external payable {
        tryNewCycle();

        _depositToken(address(0), msg.value);
    }

    function deposit(uint256 amount, address token) external nonReentrant {
        tryNewCycle();

        require(token != address(stakingToken), "Cannot deposit Staking token");
        require(token != address(0), "Use native transfer to deposit default token");

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        _depositToken(token, amount);
    }

    function getStakedAmount(address user, uint256 cycleIndex) public view returns (uint256) {
        StakeRecord[] memory stakeRecords = UserStakeRecords[user];

        // print the stake records
        console.log("will print stake records for user %s", user);
        for (uint i = 0; i < stakeRecords.length; i++) {
            console.log("StakeRecords: cycleIndex %d, stake mount %d", stakeRecords[i].cycleIndex, stakeRecords[i].amount);
        }

        for (uint i = stakeRecords.length - 1; ; i--) {

            // stakeRecords里面的对应周期的质押数据，都是对应周期发起的操作导致的状态，所以需要进入下一个周期才会生效，所以这里使用 < 而不是 <=
            if (stakeRecords[i].cycleIndex < cycleIndex) {
                return stakeRecords[i].amount;
            }

            if (i == 0) {
                break;
            }
        }

        return 0;
    }

    // stake tokens to next cycle
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        require(IERC20(stakingToken).transferFrom(msg.sender, address(this), amount), "Stake failed");

        console.log("user stake ===> amount %d, cycle %d, user %s", amount, currentCycleIndex, msg.sender);

        StakeRecord[] storage stakeRecords = UserStakeRecords[msg.sender];
        if (stakeRecords.length == 0) {
            stakeRecords.push(StakeRecord(currentCycleIndex, amount));
        } else {
            StakeRecord storage lastStakeRecord = stakeRecords[stakeRecords.length - 1];
            if (lastStakeRecord.cycleIndex == currentCycleIndex) {
                lastStakeRecord.amount += amount;
            } else {
                stakeRecords.push(StakeRecord(currentCycleIndex, lastStakeRecord.amount + amount));
            }
        }

        // update the total staked amount of the contract
        totalStaked += amount;

        // emit the stake event
        emit Stake(msg.sender, amount);
    }

    // withdraw staking tokens from current first and then next cycles
    // withdraw amount must be less than or equal to the staked amount
    function unstake(uint256 amount) external nonReentrant {
        StakeRecord[] storage stakeRecords = UserStakeRecords[msg.sender];
        require(stakeRecords.length > 0, "No stake record found");
        
        console.log("user unstake <=== amount %d, cycle %d, user %s", amount, currentCycleIndex, msg.sender);

        // get the last stake record of the user
        StakeRecord storage lastStakeRecord = stakeRecords[stakeRecords.length - 1];
        require(lastStakeRecord.amount >= amount, "Insufficient staked amount");

        // 如果存在当前周期的质押操作，那么这个质押操作是可以直接撤销的不影响周期数据(当前质押要在下个周期进入cycleInfo中)
        // 如果不是当前周期的质押操作，或者当前周期的质押数量不足，那么这个质押操作是需要从上个周期关联的cycleInfo数据中减去的
        console.log("unstaking amount %d", amount);
        console.log("currentCycleIndex %d, lastStakeRecord.cycleIndex %d, amount %d", currentCycleIndex, lastStakeRecord.cycleIndex, lastStakeRecord.amount);
        console.log("lastStakeRecord.cycleIndex %d", lastStakeRecord.cycleIndex);
        if (lastStakeRecord.cycleIndex == currentCycleIndex) {

            uint256 newAmount = 0;
            if (stakeRecords.length > 1) {
                StakeRecord memory prevStakeRecord = stakeRecords[stakeRecords.length - 2];
                if (prevStakeRecord.amount < lastStakeRecord.amount) {
                    newAmount = lastStakeRecord.amount - prevStakeRecord.amount;
                }
            } else {
                newAmount = lastStakeRecord.amount;
            }

            if (newAmount >= amount) {
                lastStakeRecord.amount -= amount;
            } else {
                uint256 diff = amount - newAmount;

                StakeRecord storage prevStakeRecord = stakeRecords[stakeRecords.length - 2];
                console.log("prevStakeRecord.amount %d", prevStakeRecord.amount);
                console.log("prevStakeRecord.cycleIndex %d", prevStakeRecord.cycleIndex);
                console.log("prevStakeRecord.totalStaked %d", cycles[prevStakeRecord.cycleIndex].totalStaked);
                
                // the last record is unstaked all and is empty, delete it
                stakeRecords.pop();

                // the prev record all unstaked with the diff amount
                prevStakeRecord.amount -= diff;

                // unstake only effect the current cycle's total staked amount
                cycles[currentCycleIndex].totalStaked -= diff;
            }
        } else {
            lastStakeRecord.amount -= amount;

            cycles[lastStakeRecord.cycleIndex + 1].totalStaked -= amount;
        }
        
        totalStaked -= amount;

        require(IERC20(stakingToken).transfer(msg.sender, amount), "Unstake failed");

        emit Unstake(msg.sender, amount);
    }

    // check point for the new cycle
    function tryNewCycle() public {
        uint256 currentBlock = block.number;
        
        CycleInfo storage currentCycle = cycles[currentCycleIndex];
        if (currentBlock - currentCycle.startBlock >= cycleMaxLength) {
            currentCycleIndex = currentCycleIndex + 1;
            console.log("enter new cycle %d, totalStaked %d", currentCycleIndex, totalStaked);
            CycleInfo storage newCycle = cycles[currentCycleIndex];
            newCycle.startBlock = currentBlock;
            newCycle.totalStaked = totalStaked;
            
            if (currentCycle.totalStaked == 0) {
                newCycle.rewards = currentCycle.rewards;
            }

            emit NewCycle(currentCycleIndex, currentBlock);
        }
    }

    // check if the user has settled the rewards for the cycle
    function isDividendWithdrawed(address user, uint256 cycleIndex, address token) public view returns (bool) {
        bytes32 key = keccak256(abi.encodePacked(user, cycleIndex, token));
        return withdrawDividendState[key];
    }

    // claim rewards for the cycle
    function withdrawDividends(uint256[] calldata cycleIndexs, address[] calldata tokens) external nonReentrant {
        require(cycleIndexs.length > 0, "No cycle index");
        require(tokens.length > 0, "No token");

        RewardInfo[] memory rewards = new RewardInfo[](cycleIndexs.length*tokens.length);
        uint256 realRewardLength = 0;

        for (uint i = 0; i < cycleIndexs.length; i++) {
            uint256 cycleIndex = cycleIndexs[i];
            require(cycleIndex < currentCycleIndex, "Cannot claim current cycle");

            // withdraw every token
            for (uint j = 0; j < tokens.length; j++) {
                address token = tokens[j];
                require(!isDividendWithdrawed(msg.sender, cycleIndex, token), "Already claimed");

                CycleInfo storage cycle = cycles[cycleIndex];

                if (cycle.totalStaked == 0) {
                    continue;
                }

                uint256 userStaked = getStakedAmount(msg.sender, cycleIndex);
                console.log("userStaked %d, cycle %d", userStaked, cycleIndex);

                // find the token reward of the cycle
                uint256 rewardAmount = 0;
                for (uint k = 0; k < cycle.rewards.length; k++) {
                    RewardInfo storage reward = cycle.rewards[k];
                    if (reward.token == token) {
                        console.log("reward.amount %d, userStaked %d, cycle.totalStaked %d", reward.amount, userStaked, cycle.totalStaked);
                        rewardAmount = reward.amount * userStaked / cycle.totalStaked;
                        break;
                    }
                }

                if (rewardAmount > 0) {
                    rewards[realRewardLength++] = RewardInfo(token, rewardAmount);
                    //rewards.push(RewardInfo(token, rewardAmount));
                }

                // set the withdraw state of the user and the cycle and the token
                bytes32 key = keccak256(abi.encodePacked(msg.sender, cycleIndex, token));
                withdrawDividendState[key] = true;
            }
        }

        // do the transfer
        for (uint i = 0; i < realRewardLength; i++) {
            RewardInfo memory reward = rewards[i];
            if (reward.token == address(0)) {
                payable(msg.sender).transfer(reward.amount);
            } else {
                IERC20(reward.token).transfer(msg.sender, reward.amount);
            }
        }
    }
}