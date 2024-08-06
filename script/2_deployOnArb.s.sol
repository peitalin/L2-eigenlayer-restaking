// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, stdJson} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {IReceiverCCIP} from "../src/IReceiverCCIP.sol";


contract DeployOnArbScript is Script {

    SenderCCIP public senderContract;
    uint256 public deployerKey;

    function run() public {
        deployerKey = vm.envUint("DEPLOYER_KEY");

        vm.startBroadcast(deployerKey);

        address router = address(0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165);
        address link = address(0xb1D4538B4571d411F07960EF2838Ce337FE1E80E);

        // deploy sender contract
        senderContract = new SenderCCIP(router, link);

        uint64 _destinationChainSelector = 16015286601757825753; // ETH Sepolia
        senderContract.allowlistDestinationChain(_destinationChainSelector, true);

        vm.stopBroadcast();
    }
}

//////////////////////////////////////////////
// Arb Sepolia
//////////////////////////////////////////////
// Router:
// 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165
//
// chain selector:
// 3478487238524512106
//
// CCIP-BnM token:
// 0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D
//////////////////////////////////////////////

//////////////////////////////////////////////
// ETH Sepolia
//////////////////////////////////////////////
// Router:
// 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59
//
// chain selector:
// 16015286601757825753
//
// CCIP-BnM token:
// 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05
//////////////////////////////////////////////
