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
import {RestakingConnector} from "../src/RestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";

import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {AgentFactory} from "../src/6551/AgentFactory.sol";



contract UpgradeReceiverOnL1Script is Script {

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    IAgentFactory public newAgentFactory;
    RestakingConnector public restakingProxy;
    ISenderCCIP public senderProxy;
    ProxyAdmin public proxyAdmin;
    IERC6551Registry public registry6551;
    IEigenAgentOwner721 public eigenAgentOwner721;

    FileReader public fileReader;
    IStrategy public strategy;
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    function run() public {
        return _run(false);
    }

    function testrun() public {
        return _run(true);
    }

    function _run(bool isTest) internal {

        vm.createSelectFork("ethsepolia");

        fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        proxyAdmin = ProxyAdmin(fileReader.readProxyAdminL1());
        senderProxy = fileReader.readSenderContract();

        DeployMockEigenlayerContractsScript deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        (
            strategy,
            strategyManager,
            , // strategyFactory
            , // pauserRegistry
            delegationManager,
            , // _rewardsCoordinator
            // token
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        (
            IReceiverCCIP receiverProxy,
            IRestakingConnector restakingConnector
        ) = fileReader.readReceiverRestakingConnector();

        (
            eigenAgentOwner721,
            registry6551
        ) = fileReader.readEigenAgent721AndRegistry();

        // deploy agentFactory
        newAgentFactory = IAgentFactory(address(
            new AgentFactory(registry6551, eigenAgentOwner721)
        ));

        // Get RestakingConnector proxy + upgrade to new implementation
        restakingProxy = RestakingConnector(address(restakingConnector));

        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(restakingProxy))),
            address(new RestakingConnector())
        );

        restakingProxy.setAgentFactory(address(newAgentFactory));
        eigenAgentOwner721.setAgentFactory(newAgentFactory);

        restakingProxy.setReceiverCCIP(address(receiverProxy));
        newAgentFactory.setRestakingConnector(address(restakingProxy));

        // Deploy new ReceiverCCIP implementation + upgrade proxy
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(receiverProxy))),
            address(new ReceiverCCIP(EthSepolia.Router, EthSepolia.Link))
        );

        require(
            address(receiverProxy.getRestakingConnector()) != address(0),
            "upgrade receiverProxy: missing restakingConnector"
        );
        require(
            address(restakingProxy.getAgentFactory()) != address(0),
            "upgrade restakingConnectorProxy: missing AgentFactory"
        );
        require(
            address(restakingProxy.getReceiverCCIP()) != address(0),
            "upgrade restakingConnectorProxy: missing ReceiverCCIP"
        );
        require(
            address(eigenAgentOwner721.getAgentFactory()) != address(0),
            "upgrade EigenAgentOwner721 NFT: missing AgentFactory"
        );
        require(
            address(newAgentFactory.getRestakingConnector()) != address(0),
            "upgrade agentFactory: missing restakingConnector"
        );

        // update AgentFactory address (as it's not behind a proxy yet)
        fileReader.saveReceiverBridgeContracts(
            isTest,
            address(receiverProxy),
            address(restakingConnector),
            address(newAgentFactory),
            address(registry6551),
            address(eigenAgentOwner721),
            address(proxyAdmin)
        );

        vm.stopBroadcast();
    }
}
