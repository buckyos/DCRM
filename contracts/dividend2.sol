
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

    function _curCycleNumber() internal view returns (uint256) {
        return lastCycleNumber;
    }

    function _getStack(address user, uint256 cycleNumber) internal view returns (uint256) {
        UserStackLog[] memory logs = userStackLog[user];
        for (uint i = logs.length-1; i < logs.length; i--) {
            if (logs[i].cycleNumber <= cycleNumber) {
                return logs[i].amount;
            }
        }

        return 0;
    }

    // 质押
    function stake(uint256 amount) public {
        dmcToken.transferFrom(msg.sender, address(this), amount);
        uint256 cycleNumber = _curCycleNumber();

        UserStackLog[] storage logs = userStackLog[msg.sender];

        if (logs.length == 0) {
            logs.push(UserStackLog(cycleNumber, amount));
        } else {
            UserStackLog storage lastLog = logs[logs.length-1];
            if (lastLog.cycleNumber == cycleNumber) {
                lastLog.amount += amount;
            } else {
                logs.push(UserStackLog(cycleNumber, lastLog.amount + amount));
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
        uint256 cycleNumber = _curCycleNumber();
        if (lastLog.cycleNumber == cycleNumber) {
            lastLog.amount -= amount;
        } else {
            logs.push(UserStackLog(cycleNumber, lastLog.amount - amount));
        }

        totalDeposits -= amount;

        dividends[cycleNumber].totalDeposits -= amount;
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
        uint256 cycleNumber = _curCycleNumber();
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
            for (uint256 i = 0; i < info.incomes.length; i++) {
                uint256 amount = info.incomes[i].amount * userStack / info.totalDeposits;
                console.log("total %d, withdraw %d", info.incomes[i].amount, amount);
                IERC20(info.incomes[i].token).transfer(msg.sender, amount);
            }
        }
        
    }
}