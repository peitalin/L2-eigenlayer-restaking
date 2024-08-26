// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {SenderUtils} from "../src/SenderUtils.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderUtils} from "../src/interfaces/ISenderUtils.sol";

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";


contract UpgradeSenderOnL2Script is Script {

    function run() public {

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        vm.createSelectFork("basesepolia");

        FileReader fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        ProxyAdmin proxyAdmin = ProxyAdmin(fileReader.readProxyAdminL2());
        ISenderCCIP senderProxy = fileReader.readSenderContract();


        /// Either use old implementation or deploy a new one if code differs.
        /// ISenderUtils senderUtils = ISenderUtils(fileReader.readSenderUtils());
        ISenderUtils senderUtils = ISenderUtils(address(new SenderUtils()));

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        SenderCCIP senderImpl = new SenderCCIP(BaseSepolia.Router, BaseSepolia.Link);

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(senderProxy))),
            address(senderImpl)
        );
        /// no need to upgradeAndCall: already initialized

        /// whitelist destination chain
        senderProxy.allowlistDestinationChain(EthSepolia.ChainSelector, true);
        senderProxy.allowlistSourceChain(EthSepolia.ChainSelector, true);
        senderProxy.setSenderUtils(senderUtils);

        vm.stopBroadcast();
    }
}
