// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {SenderUtils} from "../src/SenderUtils.sol";

import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderUtils} from "../src/interfaces/ISenderUtils.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";


contract UpgradeReceiverOnL1Script is Script {

    function run() public {

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerKey);

        vm.createSelectFork("ethsepolia");

        FileReader fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        ProxyAdmin proxyAdmin = ProxyAdmin(fileReader.readProxyAdminL1());
        ISenderCCIP senderProxy = fileReader.readSenderContract();
        RestakingConnector restakingConnector;

        DeployMockEigenlayerContractsScript deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
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

        // Either use old implementation or deploy a new one if code differs.
        restakingConnector = new RestakingConnector();
        restakingConnector.addAdmin(deployer);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);
        (
            IReceiverCCIP receiverProxy,
            // restakingConnector
        ) = fileReader.readReceiverRestakingConnector();

        // deploy receiver contract
        ReceiverCCIP receiverImpl = new ReceiverCCIP(EthSepolia.Router, EthSepolia.Link);

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(receiverProxy))),
            address(receiverImpl)
        );
        // no need to upgradeAndCall: already initialized

        receiverProxy.setSenderContractL2Addr(address(senderProxy));
        receiverProxy.setRestakingConnector(IRestakingConnector(address(restakingConnector)));

        vm.stopBroadcast();
    }
}
