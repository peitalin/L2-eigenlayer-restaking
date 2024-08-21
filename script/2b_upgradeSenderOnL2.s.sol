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

    uint256 public deployerKey;

    function run() public returns (ISenderCCIP) {
        deployerKey = vm.envUint("DEPLOYER_KEY");

        FileReader fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        ProxyAdmin proxyAdmin = ProxyAdmin(fileReader.getSenderProxyAdmin());
        ISenderCCIP senderProxy = fileReader.getSenderContract();

        // Either use old implementation or deploy a new one if code differs.
        ISenderUtils senderUtils = ISenderUtils(fileReader.getSenderUtils());
        // SenderUtils senderUtils = new SenderUtils();

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        SenderCCIP senderImpl = new SenderCCIP(BaseSepolia.Router, BaseSepolia.Link);

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(senderProxy))),
            address(senderImpl)
        );
        // no need to upgradeAndCall: already initialized

        // whitelist destination chain
        senderProxy.allowlistDestinationChain(EthSepolia.ChainSelector, true);
        vm.stopBroadcast();

        return ISenderCCIP(address(senderProxy));
    }
}
