// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./dmc2.sol";
import "./gwt2.sol";
import "./dividend.sol";

contract Exchange2 {
    address dmcToken;
    address gwtToken;
    address fundationIncome;

    // 当前周期，也可以看做周期总数
    uint256 current_circle = 0;
    uint256 current_mine_circle_start;

    // 这个周期内还能mint多少DMC
    uint256 remain_dmc_balance = 0;

    // 这个周期的能mint的DMC总量
    uint256 current_circle_dmc_balance = 0;
    uint256 current_finish_time = 0;
    uint256 public dmc2gwt_rate = 210;

    // 总共未mint的DMC总量，这个值会慢慢释放掉
    uint256 total_addtion_dmc_balance = 0;

    // 没有挖完的周期总数
    uint256 addtion_circle_count = 0;
    
    // 周期的最小时长
    uint256 min_circle_time = 100;

    //uint256 total_mine_period = 420;
    uint256 adjust_period = 21;
    uint256 initial_dmc_balance=768242.27 ether;


    constructor(address _dmcToken, address _gwtToken, address _fundationIncome, uint256 _min_circle_time) {
        dmcToken = _dmcToken;
        gwtToken = _gwtToken;
        fundationIncome = _fundationIncome;
        min_circle_time = _min_circle_time;

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
        console.log("new cycle %d start at %d, dmc balance %d", current_circle, current_mine_circle_start, current_circle_dmc_balance);
    }

    function adjustExchangeRate() internal {
        if(block.timestamp >= current_mine_circle_start + min_circle_time) {
            //结束当前挖矿周期

            if(remain_dmc_balance > 0) {
                total_addtion_dmc_balance += remain_dmc_balance;
                addtion_circle_count += 1;

                console.log("prev cycle dmc balance left %d, total left %d, total left cycle %d", remain_dmc_balance, total_addtion_dmc_balance, addtion_circle_count);

                //本周期未挖完，降低dmc2gwt_rate
                dmc2gwt_rate = dmc2gwt_rate * (1-remain_dmc_balance/current_circle_dmc_balance);
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
                if(dmc2gwt_rate > 210) {
                    // 为了测试，最高值也为210
                    dmc2gwt_rate = 210;
                }
                console.log("increase dmc2gwt_rate to %d", dmc2gwt_rate);
            }

            _newCycle();
        } else {
            console.log("keep cycle.");
            require(remain_dmc_balance > 0, "no dmc balance in current circle");
        }
    }

    function DMCtoGWT(uint256 amount) public {
        DMC2(dmcToken).burnFrom(msg.sender, amount);
        GWTToken2(gwtToken).mint(msg.sender, amount * dmc2gwt_rate * 6 / 5);
    }

    function GWTtoDMC(uint256 amount) public {
        adjustExchangeRate();
        uint256 real_dmc_count = 0;
        uint256 dmc_count = amount / dmc2gwt_rate;
        console.log("exchange dmc %d from amount %d, rate %d", dmc_count, amount, dmc2gwt_rate);
        if(dmc_count >= remain_dmc_balance) {
            current_finish_time = block.timestamp;
            
            real_dmc_count = remain_dmc_balance;
            remain_dmc_balance = 0;
            //不用立刻转给分红合约，而是等积累一下
            GWTToken2(gwtToken).transferFrom(msg.sender, address(this), real_dmc_count * dmc2gwt_rate);
            DMC2(dmcToken).mint(msg.sender, real_dmc_count);
        } else {
            remain_dmc_balance -= dmc_count;
            //不用立刻转给分红合约，而是等积累一下
            GWTToken2(gwtToken).transferFrom(msg.sender, address(this), amount);
            DMC2(dmcToken).mint(msg.sender, dmc_count);
        }
    }
    
    // 手工将累积的收入打给分红合约
    function transferIncome() public {
        GWTToken2(gwtToken).approve(fundationIncome, GWTToken2(gwtToken).balanceOf(address(this)));
        DividendContract(payable(fundationIncome)).deposit(GWTToken2(gwtToken).balanceOf(address(this)), address(gwtToken));
    }

    function getCycleInfo() public view returns (uint256, uint256, uint256) {
        return (current_circle, remain_dmc_balance, current_circle_dmc_balance);
    }
}