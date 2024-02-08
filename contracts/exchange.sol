// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./dmc.sol";
import "./gwt.sol";

contract Exchange is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    DMCToken dmcToken;
    GWTToken gwtToken;
    mapping (bytes32 => uint256) _mintDMC;

    address mintAdmin;
    function initialize(address _dmcToken, address _gwtToken) public initializer {
        __ExchangeUpgradable_init(_dmcToken, _gwtToken);
    }

    function __ExchangeUpgradable_init(address _dmcToken, address _gwtToken) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        dmcToken = DMCToken(_dmcToken);
        gwtToken = GWTToken(_gwtToken);
        mintAdmin = msg.sender;
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {
        
    }

    function setMintAdmin(address _mintAdmin) public onlyOwner {
        mintAdmin = _mintAdmin;
    }

    function allowMintDMC(address[] calldata mintAddr, string[] calldata cookie, uint256[] calldata amount) public {
        require(msg.sender == mintAdmin, "not mint admin");
        for (uint i = 0; i < mintAddr.length; i++) {
             _mintDMC[keccak256(abi.encode(mintAddr[i], cookie[i]))] = amount[i];
        }
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

    function mintDMC(string calldata cookie) public {
        bytes32 cookieHash = keccak256(abi.encode(msg.sender, cookie));
        require(_mintDMC[cookieHash] > 0, "cannot mint");
        dmcToken.mint(msg.sender, _mintDMC[cookieHash]);
        _mintDMC[cookieHash] = 0;
    }
}