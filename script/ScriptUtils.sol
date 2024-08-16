// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";
import {FileReader} from "./Addresses.sol";
import {ArbSepolia, EthSepolia} from "./Addresses.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract ScriptUtils is Script {

    function topupSenderEthBalance(address _senderAddr) public {
        if (_senderAddr.balance < 0.02 ether) {
            (bool sent, ) = address(_senderAddr).call{value: 0.05 ether}("");
            require(sent, "Failed to send Ether");
        }
    }

    function topupSenderLINKBalance(address _senderAddr, address _deployerAddr) public {
        /// Only if using sendMessagePayLINK()
        IERC20 linkTokenOnArb = IERC20(ArbSepolia.Link);
        // check LINK balances for sender contract
        uint256 senderLinkBalance = linkTokenOnArb.balanceOf(_senderAddr);

        if (senderLinkBalance < 2 ether) {
            linkTokenOnArb.approve(_deployerAddr, 2 ether);
            linkTokenOnArb.transferFrom(_deployerAddr, _senderAddr, 2 ether);
        }
        //// Approve senderContract to send LINK tokens for fees
        linkTokenOnArb.approve(_senderAddr, 2 ether);
    }

}
