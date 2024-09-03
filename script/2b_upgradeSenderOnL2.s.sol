// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script, console} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {SenderUtils} from "../src/SenderUtils.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderUtils} from "../src/interfaces/ISenderUtils.sol";

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";


contract UpgradeSenderOnL2Script is Script, FileReader {

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    function run() public {
        return _run(false);
    }

    function mockrun() public {
        vm.createSelectFork("basesepolia");
        return _run(true);
    }

    function _run(bool isTest) public {

        ProxyAdmin proxyAdmin = ProxyAdmin(readProxyAdminL2());

        (
            IReceiverCCIP receiverProxy,
            // restakingConnectorProxy
        ) = readReceiverRestakingConnector();

        ISenderCCIP senderProxy = readSenderContract();
        ISenderUtils senderUtilsProxy = readSenderUtils();

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(senderProxy))),
            address(new SenderCCIP(BaseSepolia.Router, BaseSepolia.Link))
        );

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(senderUtilsProxy))),
            address(new SenderUtils())
        );

        /// whitelist destination chain
        senderProxy.allowlistDestinationChain(EthSepolia.ChainSelector, true);
        senderProxy.allowlistSourceChain(EthSepolia.ChainSelector, true);
        senderProxy.allowlistSender(address(receiverProxy), true);

        senderProxy.setSenderUtils(senderUtilsProxy);
        senderUtilsProxy.setSenderCCIP(address(senderProxy));

        require(
            address(senderProxy.getSenderUtils()) != address(0),
            "senderProxy: missing senderUtils"
        );
        require(
            address(senderUtilsProxy.getSenderCCIP()) != address(0),
            "senderUtilsProxy: missing senderCCIP"
        );
        require(
            senderProxy.allowlistedSenders(address(receiverProxy)),
            "senderProxy: must allowlistSender(receiverProxy)"
        );
        require(
            senderProxy.allowlistedSourceChains(EthSepolia.ChainSelector),
            "senderProxy: must allowlist SourceChain: EthSepolia"
        );
        require(
            senderProxy.allowlistedDestinationChains(EthSepolia.ChainSelector),
            "senderProxy: must allowlist DestinationChain: EthSepolia)"
        );

        vm.stopBroadcast();
    }
}
