// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";

contract ScriptUtils is Script {

    uint256 public amountToTopup = 0.15 ether;

    function topupSenderEthBalance(address _senderAddr) public {
        if (_senderAddr.balance < 0.05 ether) {
            (bool sent, ) = payable(address(_senderAddr)).call{value: amountToTopup}("");
            require(sent, "Failed to send Ether");
        }
    }
}
