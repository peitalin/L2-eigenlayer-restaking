// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ITransparentUpgradeableProxy} from "@openzeppelin-v5-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-v5-contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";
import {UpgradesOZ5} from "./UpgradesOZ5.sol";


contract UpgradeSenderOnL2Script is Script, FileReader, UpgradesOZ5 {

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    function run() public {
        return _run();
    }

    function mockrun() public {
        vm.createSelectFork("basesepolia");
        return _run();
    }

    function _run() private {

        (
            IReceiverCCIP receiverProxy,
            // restakingConnectorProxy
        ) = readReceiverRestakingConnector();

        ISenderCCIP senderProxy = readSenderContract();
        ISenderHooks senderHooksProxy = readSenderHooks();

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        ProxyAdmin(getProxyAdminOZ5(address(senderProxy)))
            .upgradeAndCall(
                ITransparentUpgradeableProxy(payable(address(senderProxy))),
                address(new SenderCCIP(BaseSepolia.Router)),
                ""
            );

        ProxyAdmin(getProxyAdminOZ5(address(senderHooksProxy)))
            .upgradeAndCall(
                ITransparentUpgradeableProxy(payable(address(senderProxy))),
                address(new SenderHooks()),
                "" // empty data, don't need to initialize
            );

        /// whitelist destination chain
        senderProxy.allowlistDestinationChain(EthSepolia.ChainSelector, true);
        senderProxy.allowlistSourceChain(EthSepolia.ChainSelector, true);
        senderProxy.allowlistSender(EthSepolia.ChainSelector, address(receiverProxy), true);
        senderProxy.setSenderHooks(senderHooksProxy);

        senderHooksProxy.setSenderCCIP(address(senderProxy));
        senderHooksProxy.setBridgeTokens(
            EthSepolia.BridgeToken,
            BaseSepolia.BridgeToken
        );

        require(
            address(senderProxy.getSenderHooks()) != address(0),
            "senderProxy: missing senderHooks"
        );
        require(
            address(senderHooksProxy.getSenderCCIP()) != address(0),
            "senderHooksProxy: missing senderCCIP"
        );
        require(
            senderProxy.allowlistedSenders(EthSepolia.ChainSelector, address(receiverProxy)),
            "senderProxy: must allowlistSender(receiverProxy) on EthSepolia"
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
