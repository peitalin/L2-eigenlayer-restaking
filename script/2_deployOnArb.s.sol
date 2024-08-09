// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {ArbSepolia, EthSepolia} from "./Addresses.sol";

contract DeployOnArbScript is Script {

    uint256 public deployerKey;

    function run() public {
        deployerKey = vm.envUint("DEPLOYER_KEY");

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);
        // deploy sender contract
        SenderCCIP senderContract = new SenderCCIP(ArbSepolia.Router, ArbSepolia.Link);
        // whitelist destination chain
        senderContract.allowlistDestinationChain(EthSepolia.ChainSelector, true);
        vm.stopBroadcast();
    }
}
