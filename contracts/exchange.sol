// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./dmc.sol";
import "./gwt.sol";

contract Exchange is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    DMCToken dmcToken;
    GWTToken gwtToken;

    function initialize(address _dmcToken, address _gwtToken) public initializer {
        __ExchangeUpgradable_init(_dmcToken, _gwtToken);
    }

    function __ExchangeUpgradable_init(address _dmcToken, address _gwtToken) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        dmcToken = DMCToken(_dmcToken);
        gwtToken = GWTToken(_gwtToken);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {
        
    }

    function gwtRate() public pure returns(uint256) {
        // 1 : 210
        return 210;
    }

    function exchangeGWT(uint256 amount) public {
        uint256 gwtAmount = amount * gwtRate();
        dmcToken.transferFrom(msg.sender, address(this), amount);
        gwtToken.mint(msg.sender, gwtAmount);
    }

    function exchangeDMC(uint256 amount) public {
        uint256 dmcAmount = amount / gwtRate();
        gwtToken.burnFrom(msg.sender, amount);
        dmcToken.transfer(msg.sender, dmcAmount);
    }
}