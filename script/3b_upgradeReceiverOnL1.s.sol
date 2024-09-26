// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";

import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {EthSepolia, BaseSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";

import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {AgentFactory} from "../src/6551/AgentFactory.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";



contract UpgradeReceiverOnL1Script is Script, FileReader {

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    IAgentFactory public agentFactoryProxy;
    ISenderCCIP public senderProxy;
    RestakingConnector public restakingConnectorImpl;
    ProxyAdmin public proxyAdmin;

    IERC6551Registry public registry6551;
    IEigenAgentOwner721 public eigenAgentOwner721Proxy;
    address public baseEigenAgent;

    IStrategy public strategy;
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IRewardsCoordinator public rewardsCoordinator;

    function run() public {
        return _run(false);
    }

    function mockrun() public {
        vm.createSelectFork("ethsepolia");
        return _run(true);
    }

    function _run(bool isTest) internal {

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerKey);

        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        (
            strategy,
            strategyManager,
            , // strategyFactory
            , // pauserRegistry
            delegationManager,
            , // _rewardsCoordinator
            // token
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        (
            IReceiverCCIP receiverProxy,
            IRestakingConnector restakingConnectorProxy
        ) = readReceiverRestakingConnector();

        (
            eigenAgentOwner721Proxy,
            registry6551
        ) = readEigenAgent721AndRegistry();
        senderProxy = readSenderContract();
        agentFactoryProxy = readAgentFactory();
        baseEigenAgent = readBaseEigenAgent();
        proxyAdmin = ProxyAdmin(readProxyAdminL1());

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);


        // upgrade 6551 EigenAgentOwner NFT
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(eigenAgentOwner721Proxy))),
            address(new EigenAgentOwner721())
        );
        eigenAgentOwner721Proxy.addToWhitelistedCallers(address(restakingConnectorProxy));

        // upgrade agentFactoryProxy
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(agentFactoryProxy))),
            address(new AgentFactory())
        );

        //////////////////////////////////////////////////
        // Upgrade proxies to new implementations
        //////////////////////////////////////////////////

        // Upgrade ReceiverCCIP proxy to new implementation
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(receiverProxy))),
            address(new ReceiverCCIP(EthSepolia.Router))
        );
        vm.stopBroadcast();

        vm.startBroadcast(deployerKey);
        // Upgrade RestakingConnector proxy to new implementation
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(restakingConnectorProxy))),
            address(new RestakingConnector())
        );

        receiverProxy.setRestakingConnector(restakingConnectorProxy);

        restakingConnectorProxy.setAgentFactory(address(agentFactoryProxy));
        restakingConnectorProxy.setReceiverCCIP(address(receiverProxy));
        restakingConnectorProxy.setBridgeTokens(
            EthSepolia.BridgeToken,
            BaseSepolia.BridgeToken
        );

        eigenAgentOwner721Proxy.setAgentFactory(agentFactoryProxy);

        agentFactoryProxy.setRestakingConnector(address(restakingConnectorProxy));
        agentFactoryProxy.set6551Registry(registry6551);
        agentFactoryProxy.setEigenAgentOwner721(eigenAgentOwner721Proxy);

        require(
            address(receiverProxy.getRestakingConnector()) != address(0),
            "upgrade receiverProxy: missing restakingConnector"
        );
        require(
            address(restakingConnectorProxy.getAgentFactory()) != address(0),
            "upgrade restakingConnectorProxy: missing AgentFactory"
        );
        require(
            address(restakingConnectorProxy.getReceiverCCIP()) != address(0),
            "upgrade restakingConnectorProxy: missing ReceiverCCIP"
        );
        require(
            address(eigenAgentOwner721Proxy.getAgentFactory()) != address(0),
            "upgrade EigenAgentOwner721 NFT: missing AgentFactory"
        );
        require(
            address(agentFactoryProxy.getRestakingConnector()) != address(0),
            "upgrade agentFactory: missing restakingConnector"
        );

        // Update addresses if need be (all proxies stay the same)
        if (!isTest) {
            saveReceiverBridgeContracts(
                address(receiverProxy),
                address(restakingConnectorProxy),
                address(agentFactoryProxy),
                address(registry6551),
                address(eigenAgentOwner721Proxy),
                address(baseEigenAgent),
                address(proxyAdmin),
                FILEPATH_BRIDGE_CONTRACTS_L1
            );
        }

        vm.stopBroadcast();
    }
}
