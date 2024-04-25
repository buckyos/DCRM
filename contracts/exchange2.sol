// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./dmc2.sol";
import "./gwt2.sol";
import "./public_data_storage2.sol";

contract Exchange2 {
    DMC2 dmcToken;
    GWTToken2 gwtToken;
    
    address fundationIncome;
    uint256 current_circle = 1;
    uint256 current_mine_circle_start;
    uint256 current_dmc_balance = 0;
    uint256 current_circle_dmc_balance = 0;
    uint256 current_finish_time = 0;
    uint256 dmc2gwt_rate = 210;
    uint256 total_addtion_dmc_balance = 0;
    uint256 addtion_circle_count = 0;
    
    uint256 min_circle_time = 100;



    constructor(address _dmcToken, address _gwtToken, address _publicDataStorage, address _fundationIncome) {
        dmcToken = DMC2(_dmcToken);
        gwtToken = GWTToken2(_gwtToken);
        publicDataStorage = PublicDataStorage2(_publicDataStorage);
        fundationIncome = _fundationIncome;
    }

    function getExchangeRate() public view returns (uint256) {
        return dmc2gwt_rate;
    }

    function getCircleBalance(uint256 circle_id) public view returns (uint256) {
        return 210000;
    }

    function burnDMCforGWT(uint256 dmc_amount) public {
        dmcToken.burnFrom(msg.sender, amount);
        gwtToken.mint(msg.sender, amount);
    }

    function mintDMCbyGWT(uint256 gwt_amount) public returns (uint256){
        if(block.timestamp > current_mine_circle_start + min_circle_time) {
            //结束当前挖矿周期
            if(current_dmc_balance > 0) {
                total_addtion_dmc_balance += current_dmc_balance;
                addtion_circle_count += 1;
                //本周期未挖完，降低dmc2gwt_rate
                dmc2gwt_rate = dmc2gwt_rate * (1-current_dmc_balance/current_circle_dmc_balance);
            } else {
                //本周期挖完了，提高dmc2gwt_rate
                dmc2gwt_rate = dmc2gwt_rate * (1+(current_finish_time-current_mine_circle_start)/min_circle_time);
            }
            
            //移动到下一个周期
            current_circle = current_circle + 1;
            current_mine_circle_start = block.timestamp;
            if(total_addtion_dmc_balance > 0) {
                uint256 this_addtion_dmc = total_dmc_balance / addtion_circle_count;
                addtion_circle_count -= 1;
                total_addtion_dmc_balance -= this_addtion_dmc;
                current_dmc_balance = this_addtion_dmc + getCircleBalance(current_circle);
            } else {
                current_dmc_balance = getCircleBalance(current_circle);
            }
            current_circle_dmc_balance = current_dmc_balance;
            
        } else {
            require(current_dmc_balance > 0, "no dmc balance in current circle");
        }
        uint256 real_dmc_count = 0;
        uint256 dmc_count = gwt_amount / getExchangeRate();
        if(dmc_count > current_dmc_balance) {
            current_finish_time = block.timestamp;
            current_dmc_balance = 0;
            real_dmc_count = current_dmc_balance;
            //不用立刻转给分红合约，而是等积累一下
            gwtToken.transferFrom(msg.sender, this, real_dmc_count*getExchangeRate());
            dmcToken.mint(msg.sender, real_dmc_count);
        } else {
            current_dmc_balance -= dmc_count;
            //不用立刻转给分红合约，而是等积累一下
            gwtToken.transferFrom(msg.sender, this, gwt_amount);
            dmcToken.mint(msg.sender, dmc_count);
        }
        
        return real_dmc_count;
    }

    function exchangeGWT(uint256 amount) public {
        uint256 rate = getExchangeRate();
        dmcToken.burnFrom(msg.sender, amount);
        gwtToken.mint(msg.sender, amount * rate);
    }

    function exchangeDMC(uint256 amount) public {
        uint256 rate = getExchangeRate();
        gwtToken.transferFrom(msg.sender, fundationIncome, amount);
        dmcToken.mint(msg.sender, amount / rate);
    }
}