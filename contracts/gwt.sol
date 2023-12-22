// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./dmc.sol";

contract GWTToken is ERC20 {
    uint256 maxExchangePerDay = 0;

    // 每天的GWT流通量，从maxExchangePerDay开始，有人兑换了就减少，有人burn了就增加
    mapping(uint256 => uint256) public supplyPerDay;
    mapping(uint256 => bool) firstExchange;
    uint256 startBlock = 0;

    uint256 blocksPerDay = 5760;

    DMCToken dmcToken;

    uint256 maxSupply;

    // 这种兑换币，是不是需要设定一个最大上限？
    constructor(address _dmcToken, uint256 _maxSupply) ERC20("Gb storage per Week Token", "GWT") {
        // _mint(msg.sender, initialSupply);
        maxSupply = _maxSupply;

        maxExchangePerDay = 10000 * 10 ** decimals();
        startBlock = block.number;
        dmcToken = DMCToken(_dmcToken);
    }

    function _DayNumber() internal view returns(uint256) {
        uint dayNumber = (block.number - startBlock) / blocksPerDay;
        if (dayNumber * blocksPerDay + startBlock < block.number) {
            dayNumber += 1;
        }
        return dayNumber;
    }

    function _calcGWTAmount(uint256 amount, uint256 remainSupply) internal pure returns(uint256) {
        // TODO: 如何确定兑换比例？
        // 先写成1：1供后续测试用
        return amount;
    }

    function _calcDMCAmount(uint256 amount, uint256 remainSupply) internal pure returns(uint256) {
        // TODO: 如何确定兑换比例？
        // 先写成1：1供后续测试用
        return amount;
    }

    function exchange(uint256 amount) public {
        uint256 day = _DayNumber();
        if (firstExchange[day] == false) {
            supplyPerDay[day] = maxExchangePerDay;
            firstExchange[day] = true;
        }
        
        uint256 remain = supplyPerDay[day];
        uint256 gwtAmount = _calcGWTAmount(amount, remain);
        require(gwtAmount <= remain, "exceed max exchange per day");
        require(gwtAmount <= maxSupply - totalSupply(), "exceed max supply");
        
        dmcToken.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, gwtAmount);
        supplyPerDay[day] -= gwtAmount;
    }

    // TODO：是否要提供兑换回去的接口？汇率要如何计算？

    function burn(uint256 amount) public {
        uint256 day = _DayNumber();
        if (firstExchange[day] == false) {
            supplyPerDay[day] = maxExchangePerDay;
            firstExchange[day] = true;
        }

        uint256 dmcAmount = _calcDMCAmount(amount, supplyPerDay[day]);

        dmcToken.transfer(msg.sender, dmcAmount);
        supplyPerDay[day] += amount;
        _burn(msg.sender, amount);
    }
}
