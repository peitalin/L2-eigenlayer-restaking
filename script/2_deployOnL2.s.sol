// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";

import {Script} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {SenderUtils} from "../src/SenderUtils.sol";
import {ISenderUtils} from "../src/interfaces/ISenderUtils.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";

contract DeployOnL2Script is Script {

    function run() public returns (ISenderCCIP) {

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        // deploy sender utils
        SenderUtils senderUtils = new SenderUtils();

        // deploy sender
        SenderCCIP senderImpl = new SenderCCIP(BaseSepolia.Router, BaseSepolia.Link);

        SenderCCIP senderProxy = SenderCCIP(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(senderImpl),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        SenderCCIP.initialize.selector,
                        ISenderUtils(address(senderUtils))
                    )
                )
            ))
        );
        // whitelist both chain to receive and send messages
        senderProxy.allowlistDestinationChain(EthSepolia.ChainSelector, true);
        senderProxy.allowlistSourceChain(EthSepolia.ChainSelector, true);
        vm.stopBroadcast();

        return ISenderCCIP(address(senderProxy));
    }
}