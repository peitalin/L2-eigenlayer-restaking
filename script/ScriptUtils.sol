// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";

contract ScriptUtils is Script {

    function topupSenderEthBalance(address _senderAddr, bool isTest) public {
        if (isTest) {
            uint256 amountToTopup = 1 ether;
            if (_senderAddr.balance < 0.5 ether) {
                vm.deal(address(_senderAddr), amountToTopup);
            }
        } else {
            uint256 amountToTopup = 0.25 ether;
            if (_senderAddr.balance < 0.05 ether) {
                (bool sent, ) = payable(address(_senderAddr)).call{value: amountToTopup}("");
                require(sent, "Failed to send Ether");
            }
        }
    }

    // tells forge coverage to ignore
    function test_ignore() private {}
}
