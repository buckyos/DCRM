// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./dmc.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DMCBridge is Ownable {
    DMC public dmc2;

    mapping(bytes32 => uint256) public dmc1_to_dmc2;

    constructor(address _dmc2) Ownable(msg.sender) {
        dmc2 = DMC(_dmc2);
    }

    /**
     * @dev Retrieves the amount of claimable DMC2 tokens for a given cookie.
     * @param cookie The cookie associated with the claimable DMC2 tokens.
     * @return The amount of claimable DMC2 tokens.
     */
    function getClaimableDMC2(string calldata cookie) public view returns (uint256) {
        return dmc1_to_dmc2[keccak256(abi.encodePacked(msg.sender, cookie))];
    }

    /**
     * @dev Registers DMC1 transfor request for claimDMC2
     * @param recvAddress The array of recipient addresses.
     * @param cookie The array of cookie values associated with each recipient.
     * @param dmc1Amount The array of DMC1 token amounts to be registered for each recipient.
     * @notice recvAddress, cookie and dmc1Amount must have the same length
     */
    function registerDMC1(address[] calldata recvAddress, string[] calldata cookie, uint256[] calldata dmc1Amount) onlyOwner public {
        for (uint i = 0; i < recvAddress.length; i++) {
            dmc1_to_dmc2[keccak256(abi.encodePacked(recvAddress[i], cookie[i]))] = dmc1Amount[i];
        }   
    }

    /**
     * @dev Allows a user to claim DMC2 tokens.
     * @param cookie The cookie string for authentication.
     * @notice cookie must same as the one used in registerDMC1
     */
    function claimDMC2(string calldata cookie) public {
        // function implementation goes here
    }
        bytes32 key = keccak256(abi.encodePacked(msg.sender, cookie));
        require(dmc1_to_dmc2[key] > 0, "no dmc1 amount");
        uint256 dmc2Amount = dmc1_to_dmc2[key];
        dmc1_to_dmc2[key] = 0;
        
        dmc2.transfer(msg.sender, dmc2Amount);
    }
    
    /**
     * @dev Allows the owner to claim remaining DMC2 tokens.
     */
    function claimRemainDMC2() public onlyOwner {
        dmc2.transfer(msg.sender, dmc2.balanceOf(address(this)));
    }
}