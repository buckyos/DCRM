pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DividendContract is ReentrancyGuard {
    address public stakingToken;
    uint256 public cycleLength;
    uint256 public cycleStartBlock;

    struct RewardInfo {
        address token;
        uint256 amount;
    }

    struct CycleInfo {
        // the stake info of the cycle
        uint256 totalStaked;
        mapping(address => uint256) staked;
        address[] stakers;

        // the reward info of the cycle       
        RewardInfo[] rewards;

        // the reward settle info of the cycle for each user
        mapping(address => bool) settled;

        // the cycle is settled or not
        bool cycleSettled;
    }

    // the cycle info of the contract
    CycleInfo[] public cycles;

    // the dividend info of the user that already settled but not withdraw yet
    mapping(address => RewardInfo[]) public dividends;

    event Deposit(uint256 amount, address token);
    event Stake(address indexed user, uint256 amount);


    constructor(address _stakingToken, uint256 _cycleLength) {
        stakingToken = _stakingToken;
        cycleLength = _cycleLength;
        cycleStartBlock = block.number;
    }

    function getCurrentCycleIndex() public view returns (uint256) {
        return (block.number - cycleStartBlock) / cycleLength;
    }

    function getCurrentCycle() internal returns (CycleInfo storage) {
        uint256 currentCycleIndex = getCurrentCycleIndex();
        if (cycles.length <= currentCycleIndex) {
            cycles.push();
        }
        return cycles[currentCycleIndex];
    }

    function getNextCycle() internal returns (CycleInfo storage) {
        uint256 currentCycleIndex = getCurrentCycleIndex();
        if (cycles.length <= currentCycleIndex + 1) {
            cycles.push();
        }

        return cycles[currentCycleIndex + 1];
    }

    // deposit token to the current cycle
    function _depositToken(address token, uint256 amount) internal {
        require(amount > 0, "Cannot deposit 0");

        RewardInfo[] storage rewards = getCurrentCycle().rewards;
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
        _depositToken(address(0), msg.value);
    }

    function deposit(uint256 amount, address token) external nonReentrant {
        require(token != address(stakingToken), "Cannot deposit Staking token");
        require(token != address(0), "Use native transfer to deposit ETH");

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        _depositToken(token, amount);
    }

    function updateTokenBalance(address token) external nonReentrant {
        require(token != address(stakingToken), "Cannot update Staking token");
  
        uint256 balance;
        if (token == address(0)) {
            // If the token address is 0, return the ETH balance of the contract
            balance = address(this).balance;
        } else {
            // If the token address is not 0, return the ERC20 token balance of the contract
            balance = IERC20(token).balanceOf(address(this));
        }

        // find the token in the rewards array and update the amount
        RewardInfo[] storage rewards = getCurrentCycle().rewards;
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i].token == token) {
                rewards[i].amount = balance;
                return;
            }
        }

        // if the token is not found in the rewards array, add it
        rewards.push(RewardInfo(token, balance));
    }


    // stake tokens to next cycle
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        require(IERC20(stakingToken).transferFrom(msg.sender, address(this), amount), "Stake failed");

        CycleInfo storage cycle = getNextCycle();

        cycle.totalStaked += amount;

        // update the stakers array if the user is not already in it
        if (cycle.staked[msg.sender] == 0) {
            cycle.stakers.push(msg.sender);
        }

        cycle.staked[msg.sender] += amount;

        emit Stake(msg.sender, amount);
    }

    // withdraw staking tokens from current first and then next cycles
    // withdraw amount must be less than or equal to the staked amount in both cycles
    function withdraw(uint256 amount) external nonReentrant {
        // TODO check point to settle cycles that need to be settled
        settleCycle();  

        CycleInfo storage currentCycle = getCurrentCycle();
        CycleInfo storage nextCycle = getNextCycle();

        uint256 total = currentCycle.staked[msg.sender] + nextCycle.staked[msg.sender];
        require(amount <= total, "Insufficient staked amount");

        if (amount <= currentCycle.staked[msg.sender]) {
            currentCycle.totalStaked -= amount;
            currentCycle.staked[msg.sender] -= amount;
        } else {
            uint256 currentCycleStaked = currentCycle.staked[msg.sender];
            currentCycle.totalStaked -= currentCycleStaked;
            currentCycle.staked[msg.sender] = 0;

            nextCycle.totalStaked -= (amount - currentCycleStaked);
            nextCycle.staked[msg.sender] -= (amount - currentCycleStaked);
        }

        require(IERC20(stakingToken).transfer(msg.sender, amount), "Withdraw failed");
    }


    /**
     * @dev Claim rewards for the current cycle
     * 结算前一个周期以及之前的所有周期(如果周期尚未结算的话)，处理如下逻辑
     * 1. 当前周期N
     * 2. 向前查找到第一个尚未结算的周期M，M-N>=1
     * 3. 对周期M进行结算：质押池不为空的话，把质押池直接赋值给周期M+1；如果质押池为空，那么直接把分红池赋值给周期M(分红池不为空的话)
     * 4. 计算完毕后，对该周期设置标志位settled=true表示已经结算完毕，不可重复结算
     */
    function settleCycle() public {
        uint256 currentCycleIndex = getCurrentCycleIndex();

        // if the current cycle is the first cycle, return directly
        if (currentCycleIndex == 0) {
            return;
        }

        // if the previous cycle is already settled, return directly
        uint256 prevCycleIndex = currentCycleIndex - 1;
        if (cycles[prevCycleIndex].cycleSettled) {
            return;
        }

        // find the first unsettled cycle from front to back
        while (prevCycleIndex > 0 && !cycles[prevCycleIndex].cycleSettled) {
            prevCycleIndex--;
        }
        if (cycles[prevCycleIndex].cycleSettled) {
            prevCycleIndex++;
        }

        require(prevCycleIndex < currentCycleIndex, "No unsettled cycle found");

        // settle the cycle from prevCycleIndex to currentCycleIndex
        for (uint256 i = prevCycleIndex; i < currentCycleIndex; i++) {
            _settleCycle(i);
        }
    }

    function _settleCycle(uint index) internal {
        CycleInfo storage lastSettledCycle = cycles[index];
        CycleInfo storage currentCycle = cycles[index + 1];

        require(lastSettledCycle.cycleSettled == false, "Cycle already settled");
        require(currentCycle.cycleSettled == false, "Cycle already settled");
        require(index < getCurrentCycleIndex(), "Cannot claim current cycle");

        // if the last settled cycle has staked amount, transfer the staked amount to the current cycle
        if (lastSettledCycle.totalStaked > 0) {
            if (currentCycle.totalStaked == 0) {
                currentCycle.totalStaked = lastSettledCycle.totalStaked;
                currentCycle.stakers = lastSettledCycle.stakers;
                for (uint256 i = 0; i < lastSettledCycle.stakers.length; i++) {
                    address staker = lastSettledCycle.stakers[i];
                    currentCycle.staked[staker] = lastSettledCycle.staked[staker];
                }
            } else {
                // merge the staked amount of the last settled cycle to the current cycle
                currentCycle.totalStaked += lastSettledCycle.totalStaked;
                for (uint256 i = 0; i < lastSettledCycle.stakers.length; i++) {
                    address staker = lastSettledCycle.stakers[i];
                    if (currentCycle.staked[staker] == 0) {
                        currentCycle.stakers.push(staker);
                    }
                    currentCycle.staked[staker] += lastSettledCycle.staked[staker];
                }
            }
            
        } else {
            // if the last settled cycle has rewards and no staked token, then transfer the rewards to the current cycle
            if (lastSettledCycle.rewards.length > 0) {
                currentCycle.rewards = lastSettledCycle.rewards;
            }
        }

        lastSettledCycle.cycleSettled = true;
    }

    // check if the user has settled the rewards for the cycle
    function isDividendSettled(address user, uint256 cycleIndex) public view returns (bool) {
        return cycles[cycleIndex].settled[user];
    }

    // claim rewards for the cycle
    function settleDevidend(uint256 cycleIndex) external nonReentrant {
        // TODO check point to settle cycles that need to be settled
        settleCycle();  

        require(cycleIndex < getCurrentCycleIndex(), "Cannot claim current cycle");
       
        CycleInfo storage cycle = cycles[cycleIndex];
        require(!cycle.settled[msg.sender], "Already claimed");

        uint256 totalStaked = cycle.totalStaked;
        uint256 userStaked = cycle.staked[msg.sender];
        require(userStaked > 0, "No staked amount");
        require(cycle.rewards.length > 0, "No reward amount");

        cycle.settled[msg.sender] = true;

        // calculate the each reward amount for the user, and then send the reward to the user
        for (uint256 i = 0; i < cycle.rewards.length; i++) {
            RewardInfo storage reward = cycle.rewards[i];
            uint256 rewardAmount = reward.amount * userStaked / totalStaked;
            if (rewardAmount > 0) {
                _addDividend(msg.sender, reward.token, rewardAmount);
            }
        }
    }

    // add dividend to user when settle the rewards
    function _addDividend(address user, address token, uint256 amount) internal {
        RewardInfo[] storage userDividends = dividends[user];
        for (uint i = 0; i < userDividends.length; i++) {
            if (userDividends[i].token == token) {
                userDividends[i].amount += amount;
                return;
            }
        }

        dividends[user].push(RewardInfo(token, amount));
    }

    // get all dividends for the user than settled but not withdraw yet
    function getDividend() public view returns (RewardInfo[] memory) {
        return dividends[msg.sender];
    }

    // withdraw all rewards for the user
    function withdrawDividend() external nonReentrant {
        address user = msg.sender;

        RewardInfo[] storage userDividends = dividends[user];
        for (uint i = 0; i < userDividends.length; i++) {
            uint256 dividend = userDividends[i].amount;
            if (dividend > 0) {
                // userDividends[i].amount = 0;
                if (userDividends[i].token == address(0)) { // 如果token地址为0，表示是ETH
                    payable(user).transfer(dividend);
                } else {
                    IERC20(userDividends[i].token).transfer(user, dividend);
                }
            }
        }

        delete dividends[user]; // delete all dividends for the user after withdraw all
    }
}