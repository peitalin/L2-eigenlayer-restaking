// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";

import {FileReader} from "./FileReader.sol";
import {Script} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderCCIPMock, SenderCCIPMock} from "../test/mocks/SenderCCIPMock.sol";
import {SenderUtils} from "../src/SenderUtils.sol";
import {ISenderUtils} from "../src/interfaces/ISenderUtils.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";


contract DeploySenderOnL2Script is Script {

    FileReader public fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    function run() public returns (ISenderCCIP) {
        return _run(false);
    }

    function mockrun() public returns (ISenderCCIPMock) {
        return ISenderCCIPMock(address(_run(true)));
    }

    function _run(bool isMockRun) internal returns (ISenderCCIP) {

        vm.startBroadcast(deployerKey);

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        // deploy sender utils proxy
        SenderUtils senderUtilsProxy = SenderUtils(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(new SenderUtils()),
                    address(proxyAdmin),
                    abi.encodeWithSelector(SenderUtils.initialize.selector)
                )
            ))
        );

        // deploy sender
        SenderCCIP senderImpl;
        if (isMockRun) {
            senderImpl = new SenderCCIPMock(BaseSepolia.Router, BaseSepolia.Link);
        } else {
            senderImpl = new SenderCCIP(BaseSepolia.Router, BaseSepolia.Link);
        }

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
        senderProxy.setSenderUtils(ISenderUtils(address(senderUtilsProxy)));

        vm.stopBroadcast();

        require(
            address(senderProxy.senderUtils()) != address(0),
            "Check script: senderProxy missing senderUtils"
        );

        if (!isMockRun) {
            fileReader.saveSenderBridgeContracts(
                address(senderProxy),
                address(senderUtilsProxy),
                address(proxyAdmin)
            );
        }

        return ISenderCCIP(address(senderProxy));
    }
}