// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./dmc2.sol";
import "./gwt2.sol";
import "./dividend.sol";

contract Exchange2 {
    DMC2 dmcToken;
    GWTToken2 gwtToken;
    DividendContract fundationIncome;

    // 当前周期，也可以看做周期总数
    uint256 current_circle = 1;
    uint256 current_mine_circle_start;

    // 这个周期内还能mint多少DMC
    uint256 remain_dmc_balance = 0;
    uint256 current_circle_dmc_balance = 0;
    uint256 current_finish_time = 0;
    uint256 dmc2gwt_rate = 210;
    uint256 total_addtion_dmc_balance = 0;

    // 没有挖完的周期总数
    uint256 addtion_circle_count = 0;
    
    uint256 min_circle_time = 100;

    constructor(address _dmcToken, address _gwtToken, address _fundationIncome) {
        dmcToken = DMC2(_dmcToken);
        gwtToken = GWTToken2(_gwtToken);
        fundationIncome = DividendContract(_fundationIncome);
    }

    function getCircleBalance(uint256 circle_id) public view returns (uint256) {
        return 210000;
    }

    function adjustExchangeRate() internal {
        if(block.timestamp > current_mine_circle_start + min_circle_time) {
            //结束当前挖矿周期
            if(remain_dmc_balance > 0) {
                total_addtion_dmc_balance += remain_dmc_balance;
                addtion_circle_count += 1;
                //本周期未挖完，降低dmc2gwt_rate
                dmc2gwt_rate = dmc2gwt_rate * (1-remain_dmc_balance/current_circle_dmc_balance);
            } else {
                //本周期挖完了，提高dmc2gwt_rate
                dmc2gwt_rate = dmc2gwt_rate * (1+(current_finish_time-current_mine_circle_start)/min_circle_time);
            }
            
            //移动到下一个周期
            current_circle = current_circle + 1;
            current_mine_circle_start = block.timestamp;

            // getCircleBalance(current_circle)的含义是？
            // 这个circle是刚开始的，这个值是不是一定是0？
            remain_dmc_balance = getCircleBalance(current_circle);

            if(total_addtion_dmc_balance > 0) {
                // 此处的addtion_circle_count一定为1，Bug?
                // total_dmc_balance是什么？
                uint256 this_addtion_dmc = total_dmc_balance / addtion_circle_count;
                addtion_circle_count -= 1;
                // 如何保证total_addtion_dmc_balance一定大于this_addtion_dmc？
                total_addtion_dmc_balance -= this_addtion_dmc;
                
                remain_dmc_balance += this_addtion_dmc;
            }
            
            current_circle_dmc_balance = remain_dmc_balance;
        } else {
            require(remain_dmc_balance > 0, "no dmc balance in current circle");
        }
    }

    function exchangeGWT(uint256 amount) public {
        dmcToken.burnFrom(msg.sender, amount);
        gwtToken.mint(msg.sender, amount * dmc2gwt_rate);
    }

    function exchangeDMC(uint256 amount) public {
        adjustExchangeRate();
        uint256 real_dmc_count = 0;
        uint256 dmc_count = amount / dmc2gwt_rate;
        if(dmc_count > remain_dmc_balance) {
            current_finish_time = block.timestamp;
            
            real_dmc_count = remain_dmc_balance;
            remain_dmc_balance = 0;
            //不用立刻转给分红合约，而是等积累一下
            gwtToken.transferFrom(msg.sender, this, real_dmc_count * dmc2gwt_rate);
            dmcToken.mint(msg.sender, real_dmc_count);
        } else {
            remain_dmc_balance -= dmc_count;
            //不用立刻转给分红合约，而是等积累一下
            gwtToken.transferFrom(msg.sender, this, amount);
            dmcToken.mint(msg.sender, dmc_count);
        }
    }
    
    // 手工将累积的收入打给分红合约
    function transferIncome() public {
        gwtToken.approve(fundationIncome, gwtToken.balanceOf(this));
        fundationIncome.deposit(gwtToken.balanceOf(this));
    }
}