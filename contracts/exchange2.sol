// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./dmc2.sol";
import "./gwt2.sol";
import "./public_data_storage2.sol";

contract Exchange2 {
    DMC2 dmcToken;
    GWTToken2 gwtToken;
    PublicDataStorage2 publicDataStorage;
    address fundationIncome;
    constructor(address _dmcToken, address _gwtToken, address _publicDataStorage, address _fundationIncome) {
        dmcToken = DMC2(_dmcToken);
        gwtToken = GWTToken2(_gwtToken);
        publicDataStorage = PublicDataStorage2(_publicDataStorage);
        fundationIncome = _fundationIncome;
    }

    function getExchangeRate() public view returns (uint256) {
        return publicDataStorage.getExchangeRate();
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