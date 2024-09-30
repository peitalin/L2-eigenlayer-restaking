// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {FileReader} from "./FileReader.sol";
import {Script} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderCCIPMock, SenderCCIPMock} from "../test/mocks/SenderCCIPMock.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";


contract DeploySenderOnL2Script is Script, FileReader {

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    function run() public returns (ISenderCCIP, ISenderHooks) {
        return _run(false);
    }

    function mockrun() public returns (ISenderCCIPMock, ISenderHooks) {

        (
            ISenderCCIP _senderContract,
            ISenderHooks _senderHooks
        ) = _run(true);

        return (
            ISenderCCIPMock(address(_senderContract)),
            _senderHooks
        );
    }

    function _run(bool isMockRun) internal returns (ISenderCCIP, ISenderHooks) {

        vm.startBroadcast(deployerKey);

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        // deploy sender utils proxy
        SenderHooks senderHooksProxy = SenderHooks(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(new SenderHooks()),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        SenderHooks.initialize.selector,
                        EthSepolia.BridgeToken,
                        BaseSepolia.BridgeToken
                    )
                )
            ))
        );

        // deploy sender
        SenderCCIP senderImpl;
        if (isMockRun) {
            senderImpl = new SenderCCIPMock(BaseSepolia.Router);
        } else {
            senderImpl = new SenderCCIP(BaseSepolia.Router);
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
        senderProxy.setSenderHooks(ISenderHooks(address(senderHooksProxy)));

        senderHooksProxy.setSenderCCIP(address(senderProxy));

        require(
            address(senderProxy.getSenderHooks()) != address(0),
            "senderProxy: missing senderHooks"
        );
        require(
            address(senderHooksProxy.getSenderCCIP()) != address(0),
            "senderHooksProxy: missing senderCCIP"
        );
        require(
            senderProxy.allowlistedSourceChains(EthSepolia.ChainSelector),
            "senderProxy: must allowlist SourceChain: EthSepolia"
        );
        require(
            senderProxy.allowlistedDestinationChains(EthSepolia.ChainSelector),
            "senderProxy: must allowlist DestinationChain: EthSepolia)"
        );

        if (!isMockRun) {
            saveSenderBridgeContracts(
                address(senderProxy),
                address(senderHooksProxy),
                address(proxyAdmin),
                FILEPATH_BRIDGE_CONTRACTS_L2
            );
        }

        vm.stopBroadcast();

        return (
            ISenderCCIP(address(senderProxy)),
            ISenderHooks(address(senderHooksProxy))
        );
    }
}