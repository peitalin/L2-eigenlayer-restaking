// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderUtils} from "../src/interfaces/ISenderUtils.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {FileReader} from "./FileReader.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";


contract DeployOnEthScript is Script {

    RestakingConnector public restakingConnector;
    ReceiverCCIP public receiverProxy;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    uint256 public deployerKey;
    address public deployer;

    function run() public returns (IReceiverCCIP, IRestakingConnector) {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        FileReader fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        ISenderCCIP senderProxy = fileReader.getSenderContract();

        (
            IStrategy strategy,
            IStrategyManager strategyManager,
            , // strategyFactory
            , // pauserRegistry
            IDelegationManager delegationManager,
            , // _rewardsCoordinator
            // token
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        // deploy restaking connector for Eigenlayer
        restakingConnector = new RestakingConnector();
        restakingConnector.addAdmin(deployer);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

        // deploy receiver contract
        ReceiverCCIP receiverImpl = new ReceiverCCIP(
            EthSepolia.Router,
            EthSepolia.Link
        );

        receiverProxy = ReceiverCCIP(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(receiverImpl),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        ReceiverCCIP.initialize.selector,
                        IRestakingConnector(address(restakingConnector)),
                        senderProxy
                    )
                )
            ))
        );

        receiverProxy.allowlistSourceChain(BaseSepolia.ChainSelector, true);
        receiverProxy.allowlistDestinationChain(BaseSepolia.ChainSelector, true);
        receiverProxy.allowlistSender(address(senderProxy), true);
        receiverProxy.setSenderContractL2Addr(address(senderProxy));

        restakingConnector.addAdmin(address(receiverProxy));

        // seed the receiver contract with a bit of ETH
        if (address(receiverProxy).balance < 0.02 ether) {
            (bool sent, ) = address(receiverProxy).call{value: 0.05 ether}("");
            require(sent, "Failed to send Ether");
        }

        vm.stopBroadcast();

        return (
            IReceiverCCIP(address(receiverProxy)),
            IRestakingConnector(address(restakingConnector))
        );
    }
}
