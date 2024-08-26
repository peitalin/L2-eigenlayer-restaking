// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";
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

import {ERC6551Registry} from "@6551/ERC6551Registry.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";


contract UpgradeReceiverOnL1Script is Script {

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    function run() public {

        vm.createSelectFork("ethsepolia");

        FileReader fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        ProxyAdmin proxyAdmin = ProxyAdmin(fileReader.readProxyAdminL1());
        ISenderCCIP senderProxy = fileReader.readSenderContract();

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

        (
            IReceiverCCIP receiverProxy,
            IRestakingConnector restakingConnectorProxy
        ) = fileReader.readReceiverRestakingConnector();

        (
            ERC6551Registry registry6551,
            EigenAgentOwner721 eigenAgentOwner721
        ) = fileReader.readEigenAgent6551Registry();

        // Deploy new RestakingConnector implementation + upgrade proxy
        RestakingConnector restakingConnectorImpl = new RestakingConnector();
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(restakingConnectorProxy))),
            address(restakingConnectorImpl)
        );

        // Deploy new ReceiverCCIP implementation + upgrade proxy
        ReceiverCCIP receiverImpl = new ReceiverCCIP(EthSepolia.Router, EthSepolia.Link);
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(receiverProxy))),
            address(receiverImpl)
        );
        // No need to upgradeAndCall:
        // restakingProxy.setEigenlayerContracts(delegationManager, strategyManager, strategy);
        // restakingProxy.addAdmin(deployer);
        // receiverProxy.setSenderContractL2Addr(address(senderProxy));
        // receiverProxy.setRestakingConnector(IRestakingConnector(address(restakingConnector)));

        vm.stopBroadcast();
    }
}
