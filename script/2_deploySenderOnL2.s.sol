// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";

import {FileReader} from "./FileReader.sol";
import {Script} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {SenderUtils} from "../src/SenderUtils.sol";
import {ISenderUtils} from "../src/interfaces/ISenderUtils.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";


contract DeploySenderOnL2Script is Script {

    function run() public returns (ISenderCCIP) {
        return _run(false);
    }

    function testrun() public returns (ISenderCCIP) {
        return _run(true);
    }

    function _run(bool isTest) internal returns (ISenderCCIP) {

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        FileReader fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying

        vm.startBroadcast(deployerKey);

        ProxyAdmin proxyAdmin = new ProxyAdmin();
        // deploy sender utils
        SenderUtils senderUtils = new SenderUtils();
        // deploy sender
        SenderCCIP senderImpl = new SenderCCIP(
            BaseSepolia.Router,
            BaseSepolia.Link,
            address(senderUtils)
        );

        SenderCCIP senderProxy = SenderCCIP(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(senderImpl),
                    address(proxyAdmin),
                    abi.encodeWithSelector(SenderCCIP.initialize.selector)
                )
            ))
        );
        // whitelist both chain to receive and send messages
        senderProxy.allowlistDestinationChain(EthSepolia.ChainSelector, true);
        senderProxy.allowlistSourceChain(EthSepolia.ChainSelector, true);
        vm.stopBroadcast();

        fileReader.saveSenderBridgeContracts(
            isTest,
            address(senderProxy),
            address(senderUtils),
            address(proxyAdmin)
        );

        return ISenderCCIP(address(senderProxy));
    }
}