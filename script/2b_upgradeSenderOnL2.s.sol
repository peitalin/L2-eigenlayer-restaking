// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ITransparentUpgradeableProxy} from "@openzeppelin-v5-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-v5-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-v5-contracts/proxy/transparent/ProxyAdmin.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC1967Utils} from "@openzeppelin-v5-contracts/proxy/ERC1967/ERC1967Utils.sol";


import {Script} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";

import {BaseSepolia, EthHolesky} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";


contract UpgradeSenderOnL2Script is Script, FileReader {

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

        // OZ5 upgradeAndCall
        ITransparentUpgradeableProxy(payable(address(senderProxy)))
            .upgradeToAndCall(address(new SenderCCIP(BaseSepolia.Router)), "");
            // empty data, don't need to initialize


        // SenderHooks senderHooksProxy = SenderHooks(
        //     payable(address(
        //         new TransparentUpgradeableProxy(
        //             address(new SenderHooks()),
        //             address(deployer),
        //             abi.encodeWithSelector(
        //                 SenderHooks.initialize.selector,
        //                 EthHolesky.BridgeToken,
        //                 BaseSepolia.BridgeToken
        //             )
        //         )
        //     ))
        // );

        ProxyAdmin proxyAdmin = ProxyAdmin(getAdminAddress(address(senderHooksProxy)));

        // ITransparentUpgradeableProxy(payable(address(senderHooksProxy)))
        //     .upgradeToAndCall(address(new SenderHooks()), "");
        //     // empty data, don't need to initialize

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(senderProxy))),
            address(new SenderHooks()),
            ""
        );

        /// whitelist destination chain
        senderProxy.allowlistDestinationChain(EthHolesky.ChainSelector, true);
        senderProxy.allowlistSourceChain(EthHolesky.ChainSelector, true);
        senderProxy.allowlistSender(address(receiverProxy), true);
        senderProxy.setSenderHooks(ISenderHooks(address(senderHooksProxy)));

        senderHooksProxy.setSenderCCIP(address(senderProxy));
        senderHooksProxy.setBridgeTokens(
            EthHolesky.BridgeToken,
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
            senderProxy.allowlistedSenders(address(receiverProxy)),
            "senderProxy: must allowlistSender(receiverProxy)"
        );
        require(
            senderProxy.allowlistedSourceChains(EthHolesky.ChainSelector),
            "senderProxy: must allowlist SourceChain: EthHolesky"
        );
        require(
            senderProxy.allowlistedDestinationChains(EthHolesky.ChainSelector),
            "senderProxy: must allowlist DestinationChain: EthHolesky)"
        );

        vm.stopBroadcast();
    }

    function getAdminAddress(address proxy) internal view returns (address) {
        address CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
        Vm vm = Vm(CHEATCODE_ADDRESS);

        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
}
