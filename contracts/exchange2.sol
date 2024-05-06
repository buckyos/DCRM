// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./dmc2.sol";
import "./gwt2.sol";
import "./dividend.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Exchange2 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    address dmcToken;
    address gwtToken;
    address fundationIncome;

    // 当前周期，也可以看做周期总数
    uint256 current_circle;
    uint256 current_mine_circle_start;

    // 这个周期内还能mint多少DMC
    uint256 remain_dmc_balance;

    // 这个周期的能mint的DMC总量
    uint256 current_circle_dmc_balance;
    uint256 current_finish_time;
    uint256 public dmc2gwt_rate;

    // 总共未mint的DMC总量，这个值会慢慢释放掉
    uint256 total_addtion_dmc_balance;

    // 没有挖完的周期总数
    uint256 addtion_circle_count;
    
    // 周期的最小时长
    uint256 min_circle_time;

    //uint256 total_mine_period = 420;
    uint256 adjust_period;
    uint256 initial_dmc_balance;

    event newCycle(uint256 cycle_number, uint256 dmc_balance, uint256 start_time);
    event gwtRateChanged(uint256 new_rate, uint256 old_rate);
    event DMCMinted(address user, uint256 amount, uint256 remain);

    function initialize(address _dmcToken, address _gwtToken, address _fundationIncome, uint256 _min_circle_time) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __Exchange2Upgradable_init(_dmcToken, _gwtToken, _fundationIncome, _min_circle_time);
    }

    function __Exchange2Upgradable_init(address _dmcToken, address _gwtToken, address _fundationIncome, uint256 _min_circle_time) public onlyInitializing {
        require(_min_circle_time > 0);
        dmcToken = _dmcToken;
        gwtToken = _gwtToken;
        fundationIncome = _fundationIncome;
        min_circle_time = _min_circle_time;

        dmc2gwt_rate = 210;
        adjust_period = 21;
        initial_dmc_balance = 768242.27 ether;

        _newCycle();
    }

    function getCircleBalance(uint256 circle) public view returns (uint256) {
        
        uint256 adjust_times = (circle-1) / adjust_period;
        uint256 balance = initial_dmc_balance;
        for (uint i = 0; i < adjust_times; i++) {
            balance = balance * 4 / 5;
        }
        return balance;
        //return 210 ether;
    }

    function _newCycle() internal {
        //移动到下一个周期
        current_circle = current_circle + 1;
        current_mine_circle_start = block.timestamp;

        remain_dmc_balance = getCircleBalance(current_circle);

        if(total_addtion_dmc_balance > 0) {
            uint256 this_addtion_dmc = total_addtion_dmc_balance / addtion_circle_count;
            total_addtion_dmc_balance -= this_addtion_dmc;
            
            remain_dmc_balance += this_addtion_dmc;
        }
        
        current_circle_dmc_balance = remain_dmc_balance;
        emit newCycle(current_circle, current_circle_dmc_balance, current_mine_circle_start);
        //console.log("new cycle %d start at %d, dmc balance %d", current_circle, current_mine_circle_start, current_circle_dmc_balance);
    }

    function adjustExchangeRate() internal {
        if(block.timestamp >= current_mine_circle_start + min_circle_time) {
            //结束当前挖矿周期
            uint256 old_rate = dmc2gwt_rate;
            if(remain_dmc_balance > 0) {
                total_addtion_dmc_balance += remain_dmc_balance;
                addtion_circle_count += 1;

                console.log("prev cycle dmc balance left %d, total left %d, total left cycle %d", remain_dmc_balance, total_addtion_dmc_balance, addtion_circle_count);

                //本周期未挖完，降低dmc2gwt_rate
                dmc2gwt_rate = dmc2gwt_rate * (1-remain_dmc_balance/current_circle_dmc_balance);
                if (dmc2gwt_rate < old_rate * 4 / 5) {
                    // 跌幅限制为20%
                    dmc2gwt_rate = old_rate * 4 / 5;
                }
                if(dmc2gwt_rate < 210) {
                    // 最低值为210
                    dmc2gwt_rate = 210;
                }
                console.log("decrease dmc2gwt_rate to %d", dmc2gwt_rate);
            } else {
                if (addtion_circle_count > 0) {
                    addtion_circle_count -= 1;
                }
                //本周期挖完了，提高dmc2gwt_rate
                dmc2gwt_rate = dmc2gwt_rate * (1+(current_finish_time-current_mine_circle_start)/min_circle_time);
                if(dmc2gwt_rate > old_rate * 6 / 5) {
                    // 涨幅限制为20%
                    dmc2gwt_rate = old_rate * 6 / 5;
                }
                /*
                    // for test
                    dmc2gwt_rate = 210；
                */
                console.log("increase dmc2gwt_rate to %d", dmc2gwt_rate);
            }

            emit gwtRateChanged(dmc2gwt_rate, old_rate);

            _newCycle();
        } else {
            console.log("keep cycle.");
            require(remain_dmc_balance > 0, "no dmc balance in current circle");
        }
    }

    function _decreaseDMCBalance(uint256 amount) internal returns (uint256, bool) {
        bool is_empty = false;
        uint256 real_amount = amount;
        if(remain_dmc_balance > amount) {
            remain_dmc_balance -= amount;
        } else {
            // 待确认：我将current_finish_time看作是一轮DMC释放完毕的时间，但这会导致gwt的汇率计算可能与GWT的实际兑换情况无关
            current_finish_time = block.timestamp;

            real_amount = remain_dmc_balance;
            remain_dmc_balance = 0;
            is_empty = true;
        }

        emit DMCMinted(msg.sender, real_amount, remain_dmc_balance);

        return (real_amount, is_empty);
    }

    function DMCtoGWT(uint256 amount) public {
        DMC2(dmcToken).burnFrom(msg.sender, amount);
        GWTToken2(gwtToken).mint(msg.sender, amount * dmc2gwt_rate * 6 / 5);
    }

    function GWTtoDMC(uint256 amount) public {
        adjustExchangeRate();
        uint256 dmc_count = amount / dmc2gwt_rate;
        console.log("exchange dmc %d from amount %d, rate %d", dmc_count, amount, dmc2gwt_rate);

        (uint256 real_dmc_amount, bool is_empty) = _decreaseDMCBalance(dmc_count);
        uint256 real_gwt_amount = amount;
        if (is_empty) {
            //current_finish_time = block.timestamp;
            real_gwt_amount = real_dmc_amount * dmc2gwt_rate;
        }

        //不用立刻转给分红合约，而是等积累一下
        GWTToken2(gwtToken).transferFrom(msg.sender, address(this), real_gwt_amount);
        DMC2(dmcToken).mint(msg.sender, real_dmc_amount);
    }
    
    // 手工将累积的收入打给分红合约
    function transferIncome() public {
        GWTToken2(gwtToken).approve(fundationIncome, GWTToken2(gwtToken).balanceOf(address(this)));
        DividendContract(payable(fundationIncome)).deposit(GWTToken2(gwtToken).balanceOf(address(this)), address(gwtToken));
    }

    function getCycleInfo() public view returns (uint256, uint256, uint256) {
        return (current_circle, remain_dmc_balance, current_circle_dmc_balance);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}