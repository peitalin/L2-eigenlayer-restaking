// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";

contract ScriptUtils is Script {

    function topupSenderEthBalance(address _senderAddr) public {
        if (_senderAddr.balance < 0.02 ether) {
            (bool sent, ) = payable(address(_senderAddr)).call{value: 0.05 ether}("");
            require(sent, "Failed to send Ether");
        }
    }
}
