// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./dmc.sol";
import "./gwt.sol";
import "./dividend.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Exchange is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    address dmcToken;
    address gwtToken;
    address fundationIncome;

    bool test_mode;
    
    // currect release cycle, also can be seen as the total cycle number
    uint256 current_circle;
    uint256 current_mine_circle_start;

    // remain DMCs can be mined in current cycle
    uint256 remain_dmc_balance;

    // total DMCs can be mined in current cycle
    uint256 current_circle_dmc_balance;
    uint256 current_finish_time;
    uint256 public dmc2gwt_rate;

    // total DMC balance not be minted in past cycles, it will be minted in future cycles slowly
    uint256 total_addtion_dmc_balance;

    // the number of cycle in which the minted DMCs not as much as current_circle_dmc_balance
    uint256 addtion_circle_count;
    
    // min circle time, in seconds
    uint256 min_circle_time;

    //uint256 total_mine_period = 420;
    uint256 adjust_period;
    uint256 initial_dmc_balance;

    uint256 free_mint_balance;
    mapping(address=>bool) is_free_minted;

    uint256 public test_dmc_balance;
    uint256 public cycle_start_time;
    uint256 public cycle_end_time;
    uint256 public test_gwt_ratio;

    event newCycle(uint256 cycle_number, uint256 dmc_balance, uint256 start_time);
    event gwtRateChanged(uint256 new_rate, uint256 old_rate);
    event DMCMinted(address user, uint256 amount, uint256 remain);

    modifier testEnabled() {
        require(test_mode, "contract not in test mode");
        _;
    }

    modifier testDisabled() {
        require(!test_mode, "contract in test mode");
        _;
    }

    function initialize(address _dmcToken, address _gwtToken, address _fundationIncome, uint256 _min_circle_time) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __ExchangeUpgradable_init(_dmcToken, _gwtToken, _fundationIncome, _min_circle_time);
    }

    function __ExchangeUpgradable_init(address _dmcToken, address _gwtToken, address _fundationIncome, uint256 _min_circle_time) public onlyInitializing {
        require(_min_circle_time > 0);
        dmcToken = _dmcToken;
        gwtToken = _gwtToken;
        fundationIncome = _fundationIncome;
        min_circle_time = _min_circle_time;

        dmc2gwt_rate = 210;
        adjust_period = 21;
        initial_dmc_balance = 4817446 ether;

        test_mode = true;
        //_newCycle();
    }

    function getCircleBalance(uint256 circle) public view returns (uint256) {
        // return 210 ether;
        
        uint256 adjust_times = (circle-1) / adjust_period;
        uint256 balance = initial_dmc_balance;
        for (uint i = 0; i < adjust_times; i++) {
            balance = balance * 4 / 5;
        }
        return balance;
    }

    function _newCycle() internal {
        //move to next cycle
        current_circle = current_circle + 1;
        current_mine_circle_start = block.timestamp;

        remain_dmc_balance = getCircleBalance(current_circle);

        if(total_addtion_dmc_balance > 0) {
            // if there has some DMCs not be mined in past cycles, we will mint some of them in next cycles
            uint256 this_addtion_dmc = total_addtion_dmc_balance / addtion_circle_count;
            total_addtion_dmc_balance -= this_addtion_dmc;
            
            remain_dmc_balance += this_addtion_dmc;
        }
        
        current_circle_dmc_balance = remain_dmc_balance;
        emit newCycle(current_circle, current_circle_dmc_balance, current_mine_circle_start);
        // console.log("new cycle %d start at %d, dmc balance %d", current_circle, current_mine_circle_start, current_circle_dmc_balance);
    }

    function adjustExchangeRate() internal {
        if(block.timestamp >= current_mine_circle_start + min_circle_time) {
            //end current cycle, calculate new exchange rate
            uint256 old_rate = dmc2gwt_rate;
            if(remain_dmc_balance > 0) {
                total_addtion_dmc_balance += remain_dmc_balance;
                addtion_circle_count += 1;

                // console.log("prev cycle dmc balance left %d, total left %d, total left cycle %d", remain_dmc_balance, total_addtion_dmc_balance, addtion_circle_count);

                //there has remaining DMCs in current cycle, decrease DMC -> GWT exchange rate
                dmc2gwt_rate = dmc2gwt_rate * (1-remain_dmc_balance/current_circle_dmc_balance);
                if (dmc2gwt_rate < old_rate * 4 / 5) {
                    // we have a limit down as 20%
                    dmc2gwt_rate = old_rate * 4 / 5;
                }
                if(dmc2gwt_rate < 210) {
                    // the lowest rate is 210
                    dmc2gwt_rate = 210;
                }
                // console.log("decrease dmc2gwt_rate to %d", dmc2gwt_rate);
            } else {
                if (addtion_circle_count > 0) {
                    addtion_circle_count -= 1;
                }
                // all DMCs in current cycle have been mined, increase DMC -> GWT exchange rate
                dmc2gwt_rate = dmc2gwt_rate * (1+(current_finish_time-current_mine_circle_start)/min_circle_time);
                if(dmc2gwt_rate > old_rate * 6 / 5) {
                    // we have a raising limit as 20%
                    dmc2gwt_rate = old_rate * 6 / 5;
                }
                // for test
                // dmc2gwt_rate = 210;
                // console.log("increase dmc2gwt_rate to %d", dmc2gwt_rate);
            }

            emit gwtRateChanged(dmc2gwt_rate, old_rate);

            _newCycle();
        } else {
            // console.log("keep cycle.");
            require(remain_dmc_balance > 0, "no dmc balance in current circle");
        }
    }

    function _decreaseDMCBalance(uint256 amount) internal returns (uint256, bool) {
        bool is_empty = false;
        uint256 real_amount = amount;
        if(remain_dmc_balance > amount) {
            remain_dmc_balance -= amount;
        } else {
            // NEED NOTICE: if we have more than one tokens needed to exchanged from DMC,they will share the DMC mint limit in one cycle
            // Rate calculation logic above may need be fixed.
            current_finish_time = block.timestamp;

            real_amount = remain_dmc_balance;
            remain_dmc_balance = 0;
            is_empty = true;
        }

        return (real_amount, is_empty);
    }

    function addFreeMintBalance(uint256 amount) public {
        require(amount > 0, "amount must be greater than 0");
        free_mint_balance += amount;
        GWT(gwtToken).transferFrom(msg.sender, address(this), amount);
    }

    function freeMintGWT() public {
        //one address only can free mint once
        //get 210 GWT
        require(!is_free_minted[msg.sender], "already free minted");
        require(free_mint_balance > 0, "no free mint balance");
        
        is_free_minted[msg.sender] = true;
        free_mint_balance -= 210 ether;
        GWT(gwtToken).transfer(msg.sender, 210 ether);
    }

    function canFreeMint() view public returns (bool) {
        return !is_free_minted[msg.sender];
    }

    function DMCtoGWT(uint256 amount) public {
        uint rate = dmc2gwt_rate;
        if (test_mode) {
            rate = test_gwt_ratio;
        }
        DMC(dmcToken).burnFrom(msg.sender, amount);
        GWT(gwtToken).mint(msg.sender, amount * rate * 11 / 10);
    }

    function enableTestMode() public onlyOwner testDisabled {
        test_mode = true;
    }

    function enableProdMode(bool isResetRatio) public onlyOwner testEnabled {
        test_mode = false;

        // return remaining DMCs to owner, those DMCs comes from owner called addFreeDMCTestMintBalance in test mode.
        DMC(dmcToken).transfer(msg.sender, DMC(dmcToken).balanceOf(address(this)));

        if (!isResetRatio) {
            dmc2gwt_rate = test_gwt_ratio;
        }

        // if its the first time to enable prod mode, we need to init a new cycle
        if (current_circle == 0) {
            _newCycle();
        }
    }

    function GWTToDMCForTest(uint256 amount) public testEnabled {
        require(test_gwt_ratio > 0, "not start test cycle");

        uint256 dmc_count = amount / test_gwt_ratio;
        uint256 real_dmc_amount = dmc_count;
        if (test_dmc_balance <= dmc_count) {
            real_dmc_amount = test_dmc_balance;
            cycle_end_time = block.timestamp;
        }

        test_dmc_balance -= real_dmc_amount;

        GWT(gwtToken).transferFrom(msg.sender, address(this), real_dmc_amount * 210);
        DMC(dmcToken).transfer(msg.sender, real_dmc_amount);
    }

    function addDMCXForTest(uint256 amount) public testEnabled {
        DMC(dmcToken).transferFrom(msg.sender, address(this), amount);
        if (amount >= 50000 ether) {
            _startNewTestCycle();
        }
    }

    function startNewTestCycle() public onlyOwner testEnabled {
        _startNewTestCycle();
    }

    function _startNewTestCycle() internal {
        if (test_gwt_ratio == 0) {  // init
            test_gwt_ratio = 210;

            cycle_start_time = block.timestamp;
            cycle_end_time = 0;
        } else if (cycle_end_time > 0) {
            uint256 cycleDuration = cycle_end_time - cycle_start_time;
            if (cycleDuration < 3 days) {
                uint256 gwt_ratio_change = (block.timestamp - cycle_end_time) * 100 / (block.timestamp - cycle_start_time);
                if (gwt_ratio_change > 20) {
                    gwt_ratio_change = 20;
                }

                test_gwt_ratio = test_gwt_ratio * (100 + gwt_ratio_change) / 100;
            } else {
                uint256 gwt_ratio_change = (cycleDuration - 3 days) * 100 / cycleDuration;
                if (gwt_ratio_change > 20) {
                    gwt_ratio_change = 20;
                }

                test_gwt_ratio = test_gwt_ratio * (100 - gwt_ratio_change) / 100;

                if (test_gwt_ratio < 210) {
                    test_gwt_ratio = 210;
                }
            }

            cycle_start_time = block.timestamp;
            cycle_end_time = 0;
        }

        test_dmc_balance = DMC(dmcToken).balanceOf(address(this));
    }

    function GWTtoDMC(uint256 amount) public testDisabled {
        adjustExchangeRate();
        uint256 dmc_count = amount / dmc2gwt_rate;
        // console.log("exchange dmc %d from amount %d, rate %d", dmc_count, amount, dmc2gwt_rate);

        (uint256 real_dmc_amount, bool is_empty) = _decreaseDMCBalance(dmc_count);
        require(real_dmc_amount > 0, "no dmc balance in current circle");
        
        uint256 real_gwt_amount = amount;
        if (is_empty) {
            //current_finish_time = block.timestamp;
            real_gwt_amount = real_dmc_amount * dmc2gwt_rate;
        }

        // The GWT received from the sender first stored in the contract address.
        GWT(gwtToken).transferFrom(msg.sender, address(this), real_gwt_amount);
        DMC(dmcToken).mint(msg.sender, real_dmc_amount);
        emit DMCMinted(msg.sender, real_dmc_amount, remain_dmc_balance);
    }
    
    // Manually transfer the remaining GWT to a income distribution contract, usually a DividendContract
    function transferIncome() public {
        uint256 income = GWT(gwtToken).balanceOf(address(this)) - free_mint_balance;
        GWT(gwtToken).approve(fundationIncome, income);
        DividendContract(payable(fundationIncome)).deposit(income, address(gwtToken));
    }

    function getCycleInfo() public view returns (uint256, uint256, uint256) {
        return (current_circle, remain_dmc_balance, current_circle_dmc_balance);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}