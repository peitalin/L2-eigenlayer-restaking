// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {TransparentUpgradeableProxy} from "@openzeppelin-v5-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-v5-contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC20Minter} from "../test/mocks/ERC20Minter.sol";

import {FileReader} from "./FileReader.sol";
import {Script} from "forge-std/Script.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderCCIPMock, SenderCCIPMock} from "../test/mocks/SenderCCIPMock.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
import {BaseSepolia, EthHolesky} from "./Addresses.sol";


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

        // deploy sender utils proxy
        SenderHooks senderHooksProxy = SenderHooks(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(new SenderHooks()),
                    address(deployer),
                    abi.encodeWithSelector(
                        SenderHooks.initialize.selector,
                        EthHolesky.BridgeToken,
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

        // Deployer, not ProxyAdmin for 2nd argument in TransparentUpgradeableProxy constructor
        // https://forum.openzeppelin.com/t/5-0-transparentupgradeableproxy-upgradeandcall-error/41540/2
        SenderCCIP senderProxy = SenderCCIP(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(senderImpl),
                    address(deployer),
                    abi.encodeWithSelector(SenderCCIP.initialize.selector)
                )
            ))
        );
        // whitelist both chain to receive and send messages
        senderProxy.allowlistDestinationChain(EthHolesky.ChainSelector, true);
        senderProxy.allowlistSourceChain(EthHolesky.ChainSelector, true);
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
            senderProxy.allowlistedSourceChains(EthHolesky.ChainSelector),
            "senderProxy: must allowlist SourceChain: EthHolesky"
        );
        require(
            senderProxy.allowlistedDestinationChains(EthHolesky.ChainSelector),
            "senderProxy: must allowlist DestinationChain: EthHolesky)"
        );

        if (!isMockRun) {
            saveSenderBridgeContracts(
                address(senderProxy),
                address(senderHooksProxy),
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