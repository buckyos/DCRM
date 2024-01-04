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
    bytes32 luckyMintRoot;
    //mapping (address => bool) allow_dmcMint;
    mapping (bytes32 => bool) luckyHashUsed;
    mapping (address => uint256) mintAfter;

    uint mintAfterTime;
    /*
    modifier onlyMinter() {
        require(allow_dmcMint[msg.sender], "mint not allowed");
        _;
    }

    function enableDMCMint(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_dmcMint[addresses[i]] = true;
        }
    }

    function disableDMCMint(address[] calldata addresses) public onlyOwner {
        for (uint i = 0; i < addresses.length; i++) {
            allow_dmcMint[addresses[i]] = false;
        }
    }
    */
    function initialize(address _dmcToken, address _gwtToken) public initializer {
        __ExchangeUpgradable_init(_dmcToken, _gwtToken);
        mintAfterTime = 1 days;
    }

    function __ExchangeUpgradable_init(address _dmcToken, address _gwtToken) internal onlyInitializing {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        dmcToken = DMCToken(_dmcToken);
        gwtToken = GWTToken(_gwtToken);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {
        
    }

    

    function setLuckyMintRoot(bytes32 _luckyMintRoot) public onlyOwner {
        luckyMintRoot = _luckyMintRoot;
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

    function mintDMC(bytes32 luckyHash, bytes32[] calldata luckyPath) public /*onlyMinter*/ {
        require(mintAfter[msg.sender] < block.timestamp, "mint too often");
        if (luckyHash != bytes32(0) && MerkleProof.verify(luckyPath, luckyMintRoot, luckyHash)) {
            require(!luckyHashUsed[luckyHash], "lucky hash used");
            dmcToken.mint(msg.sender, 2100 * 10 ** dmcToken.decimals());
            luckyHashUsed[luckyHash] = true;
        } else {
            dmcToken.mint(msg.sender, 210 * 10 ** dmcToken.decimals());
        }

        mintAfter[msg.sender] = block.timestamp + mintAfterTime;
    }
}