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
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {AgentFactory} from "../src/6551/AgentFactory.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";



contract UpgradeReceiverOnL1Script is Script {

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    IAgentFactory public agentFactoryProxy;
    ISenderCCIP public senderProxy;
    ProxyAdmin public proxyAdmin;
    IERC6551Registry public registry6551;
    IEigenAgentOwner721 public eigenAgentOwner721Proxy;

    RestakingConnector public restakingConnectorImpl;

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

        fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
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

        (
            IReceiverCCIP receiverProxy,
            IRestakingConnector restakingProxy
        ) = fileReader.readReceiverRestakingConnector();

        (
            eigenAgentOwner721Proxy,
            // registry6551
        ) = fileReader.readEigenAgent721AndRegistry();

        agentFactoryProxy = fileReader.readAgentFactory();
        proxyAdmin = ProxyAdmin(fileReader.readProxyAdminL1());

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);


        // upgrade 6551 EigenAgentOwner NFT
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(eigenAgentOwner721Proxy))),
            address(new EigenAgentOwner721())
        );
        eigenAgentOwner721Proxy.addToWhitelistedCallers(address(restakingProxy));

        // deploy new 6551 Registry
        registry6551 = IERC6551Registry(address(new ERC6551Registry()));

        // upgrade agentFactoryProxy
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(agentFactoryProxy))),
            address(new AgentFactory(registry6551, eigenAgentOwner721Proxy))
        );

        //////////////////////////////////////////////////
        // Upgrade proxies to new implementations
        //////////////////////////////////////////////////

        // Upgrade ReceiverCCIP proxy to new implementation
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(receiverProxy))),
            address(new ReceiverCCIP(EthSepolia.Router, EthSepolia.Link))
        );
        vm.stopBroadcast();

        vm.startBroadcast(deployerKey);
        // Upgrade RestakingConnector proxy to new implementation
        proxyAdmin.upgrade(
            TransparentUpgradeableProxy(payable(address(restakingProxy))),
            address(new RestakingConnector())
        );
        restakingProxy.setAgentFactory(address(agentFactoryProxy));
        eigenAgentOwner721Proxy.setAgentFactory(agentFactoryProxy);
        restakingProxy.setReceiverCCIP(address(receiverProxy));
        agentFactoryProxy.setRestakingConnector(address(restakingProxy));

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
            address(eigenAgentOwner721Proxy.getAgentFactory()) != address(0),
            "upgrade EigenAgentOwner721 NFT: missing AgentFactory"
        );
        require(
            address(agentFactoryProxy.getRestakingConnector()) != address(0),
            "upgrade agentFactory: missing restakingConnector"
        );

        // Update registry6551 address, all other proxies stay the same
        fileReader.saveReceiverBridgeContracts(
            isTest,
            address(receiverProxy),
            address(restakingProxy),
            address(agentFactoryProxy),
            address(registry6551),
            address(eigenAgentOwner721Proxy),
            address(proxyAdmin)
        );

        vm.stopBroadcast();
    }
}
