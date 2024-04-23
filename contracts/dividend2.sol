
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "hardhat/console.sol";


// 这里打算做一个更简单的逻辑：一旦有抵押变动，这个用户在这一轮里就不能提取收益
contract Dividend2 {
    IERC20 dmcToken;
    uint256 minCycleBlock;
    uint256 startBlock;

    uint256 lastActiveCycle;

    struct TokenIncome {
        address token;
        uint256 amount;
    }

    struct DividendInfo {
        uint256 startBlock;
        uint256 totalDeposits;
        TokenIncome[] incomes;
    }

    struct UserStackLog {
        uint256 cycleNumber;
        uint256 amount;
        uint256 addAmount;
    }

    mapping(uint256 => DividendInfo) dividends;
    uint256 lastCycleNumber;

    uint256 totalDeposits;

    mapping(address => UserStackLog[]) userStackLog;

    constructor(address _dmcToken, uint256 _minCycleBlock) {
        dmcToken = IERC20(_dmcToken);
        minCycleBlock = _minCycleBlock;
        startBlock = block.number;
    }

    // TODO：可能改成uint256[] cycleNumbers，返回uint256[]更好，考虑到withdraw的大多数调用情况应该是一次提取多个周期
    function _getStack(address user, uint256 cycleNumber) internal view returns (uint256) {
        UserStackLog[] memory logs = userStackLog[user];
        for (uint i = logs.length-1; i >= 0; i--) {
            if (logs[i].cycleNumber <= cycleNumber) {
                return logs[i].amount;
            }
        }

        return 0;
    }

    // 质押
    function stake(uint256 amount) public {
        dmcToken.transferFrom(msg.sender, address(this), amount);
        uint256 nextCycle = lastCycleNumber + 1;

        UserStackLog[] storage logs = userStackLog[msg.sender];

        if (logs.length == 0) {
            logs.push(UserStackLog(nextCycle, amount, amount));
        } else {
            UserStackLog storage lastLog = logs[logs.length-1];
            if (lastLog.cycleNumber == nextCycle) {
                lastLog.amount += amount;
                lastLog.addAmount += amount;
            } else {
                logs.push(UserStackLog(nextCycle, lastLog.amount + amount, amount));
            }
        }

        totalDeposits += amount;
        console.log("total deposit %d", totalDeposits);
    }

    // 提取
    function unStake(uint256 amount) public {
        UserStackLog[] storage logs = userStackLog[msg.sender];
        require(logs.length > 0, "no deposit");

        UserStackLog storage lastLog = logs[logs.length-1];
        require(lastLog.amount >= amount, "not enough deposit");
        
        dmcToken.transfer(msg.sender, amount);
        uint256 nextCycle = lastCycleNumber + 1;

        if (lastLog.cycleNumber == nextCycle) {
            
            if (lastLog.addAmount >= amount) {
                lastLog.amount -= amount;
                lastLog.addAmount -= amount;
            } else {
                uint256 diff = amount - lastLog.addAmount;

                // 从上一个周期扣amount的差值, 能走到这里，一定说明至少有两个周期，否则不会出现lastLog.amount >= amount 且 lastLog.addAmount < amount的情况
                UserStackLog memory lastLastLog = logs[logs.length-2];
                
                // 假设当前是周期3，用户在周期1存了50，周期3存了20，又提取了45
                // 这里的Log要从[{2, 50, 50}, {4, 70, 20}]变成[{2, 50, 50}, {3, 25, 25}, {4, 25, 0}]
                if (lastLastLog.cycleNumber != nextCycle - 1) {
                    // 4 -> 3
                    lastLog.cycleNumber = nextCycle - 1;
                    // 70 -> 25 = 50 - (45 - 20)
                    lastLog.amount = lastLastLog.amount - diff;
                    // addAmount不改了，因为这个值在非lastLog的位置并没有意义

                    logs.push(UserStackLog(nextCycle, lastLog.amount, 0));
                } else {
                    // 假设用户在周期2存了50，周期3存了20，又提取了45
                    // 这里的原log为[{3, 50, 50}, {4, 70, 20}]，变成[{3, 25, 25}, {4, 25, 0}]
                    lastLastLog.amount -= diff;
                    // addAmount不改了，因为这个值在非lastLog的位置并没有意义
                    lastLog.amount -= amount;
                    // 这里的addAmount就必须要改
                    lastLog.addAmount = 0;
                }
                
                dividends[lastLog.cycleNumber].totalDeposits -= diff;
            }
        } else {
            logs.push(UserStackLog(cycleNumber, lastLog.amount - amount, 0));
        }

        totalDeposits -= amount;
    }

    function _settleCycle() internal {
        DividendInfo memory lastInfo = dividends[lastCycleNumber];
        console.log("try check cycle, last %d, cur %d", lastInfo.startBlock, block.number);
        if (lastInfo.startBlock + minCycleBlock > block.number) {
            console.log("in cur cycle, skip.");
            return;
        }

        lastCycleNumber += 1;

        console.log("new cycle %d", lastCycleNumber);
        DividendInfo storage newInfo = dividends[lastCycleNumber];
        newInfo.startBlock = block.number;

        console.log("new cycle total deposit %d", totalDeposits);
        newInfo.totalDeposits = totalDeposits;

        if (lastInfo.totalDeposits == 0) {
            // 没人质押，分红滚入下一期
            newInfo.incomes = lastInfo.incomes;
        }
    }

    // 简单起见，先只做erc20的
    function deposit(uint256 amount, address token) public {
        _settleCycle();

        // 当amount为0时，强制结算上一个周期
        if (amount == 0) {
            return;
        }

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        uint256 cycleNumber = lastCycleNumber;
        TokenIncome[] storage incomes = dividends[cycleNumber].incomes;
        if (incomes.length == 0) {
            dividends[cycleNumber].incomes.push(TokenIncome(token, amount));
        } else {
            bool found = false;
            for (uint i = 0; i < dividends[cycleNumber].incomes.length; i++) {
                console.log("get token %d", i);
                if (dividends[cycleNumber].incomes[i].token == token) {
                    dividends[cycleNumber].incomes[i].amount += amount;
                    found = true;
                    break;
                }
            }

            if (!found) {
                dividends[cycleNumber].incomes.push(TokenIncome(token, amount));
            }
        }
        
    }

    function withdraw(uint256[] calldata cycleNumbers) public {
        for (uint i = 0; i < cycleNumbers.length; i++) {
            console.log("%s withdraw %d", msg.sender, cycleNumbers[i]);
            uint256 cycleNumber = cycleNumbers[i];
            DividendInfo memory info = dividends[cycleNumber];
            require(info.totalDeposits > 0, "no dividend");
            
            uint256 userStack = _getStack(msg.sender, cycleNumber);
            console.log("get stack %d at cycle %d", userStack, cycleNumber);
            console.log("get total stack %d at cycle %d", info.totalDeposits, cycleNumber);
            require(userStack > 0, "cannot withdraw");
            for (uint256 i = 0; i < info.incomes.length; i++) {
                uint256 amount = info.incomes[i].amount * userStack / info.totalDeposits;
                console.log("total %d, withdraw %d", info.incomes[i].amount, amount);
                IERC20(info.incomes[i].token).transfer(msg.sender, amount);
            }
        }
        
    }
}