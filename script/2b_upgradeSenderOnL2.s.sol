// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script, console} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {SenderUtils} from "../src/SenderUtils.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderUtils} from "../src/interfaces/ISenderUtils.sol";

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";


contract UpgradeSenderOnL2Script is Script {


    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    function run() public {

        uint256 l2ForkId = vm.createSelectFork("basesepolia");

        FileReader fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying

        ProxyAdmin proxyAdmin = ProxyAdmin(fileReader.readProxyAdminL2());
        ISenderCCIP senderProxy = fileReader.readSenderContract();

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        SenderCCIP senderImpl = new SenderCCIP(BaseSepolia.Router, BaseSepolia.Link);

        ISenderUtils senderUtils = ISenderUtils(address(new SenderUtils()));

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(senderProxy))),
            address(senderImpl)
        );

        /// whitelist destination chain
        senderProxy.allowlistDestinationChain(EthSepolia.ChainSelector, true);
        senderProxy.allowlistSourceChain(EthSepolia.ChainSelector, true);
        senderProxy.setSenderUtils(senderUtils);

        require(
            address(senderProxy.getSenderUtils()) != address(0),
            "Check script: senderProxy missing senderUtils"
        );

        vm.stopBroadcast();
    }
}
