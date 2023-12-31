// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./dmc.sol";

contract GWTToken is ERC20, Ownable {
    DMCToken dmcToken;
    mapping (address => bool) allow_transfer;

    // 这种兑换币，是不是需要设定一个最大上限？
    constructor(address _dmcToken) ERC20("Gb storage per Week Token", "GWT") Ownable(msg.sender) {
        dmcToken = DMCToken(_dmcToken);
        // enable mint and burn
        allow_transfer[address(0)] = true;
    }

    function enableTransfer(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_transfer[addresses[i]] = true;
        }
    }

    function disableTransfer(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_transfer[addresses[i]] = false;
        }
    }

    function _calcGWTAmount(uint256 dmc_amount) internal pure returns(uint256) {
        // 1 : 210
        return dmc_amount * 210;
    }

    function _calcDMCAmount(uint256 gwt_amount) internal pure returns(uint256) {
        // 210 : 1
        return gwt_amount / 210;
    }

    function _update(address sender, address to, uint256 amount) internal override {
        require(allow_transfer[sender] || allow_transfer[to], "transfer not allowed");
        super._update(sender, to, amount);
    }


    //REVIEW 把兑换合约独立出去，GWT合约只需要认兑换合约（而不是认DMC合约）就可以。
    //  兑换合约是可升级逻辑的。
    function exchange(uint256 amount) public {        
        uint256 gwtAmount = _calcGWTAmount(amount);
        
        dmcToken.transferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, gwtAmount);
    }

    function burn(uint256 amount) public {
        uint256 dmcAmount = _calcDMCAmount(amount);

        dmcToken.transfer(msg.sender, dmcAmount);
        _burn(msg.sender, amount);
    }
}
