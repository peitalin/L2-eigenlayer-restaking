// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderUtils} from "../src/interfaces/ISenderUtils.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {FileReader} from "./FileReader.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";

import {AgentFactory} from "../src/6551/AgentFactory.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";

import {ERC6551Registry} from "@6551/ERC6551Registry.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";



contract DeployReceiverOnL1Script is Script {

    RestakingConnector public restakingProxy;
    ReceiverCCIP public receiverProxy;
    ISenderCCIP public senderContract;
    ProxyAdmin public proxyAdmin;
    IERC6551Registry public registry6551;
    IEigenAgentOwner721 public eigenAgentOwner721;
    IAgentFactory public agentFactoryProxy;

    FileReader public fileReader;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    IStrategy public strategy;
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;

    uint256 public deployerKey = vm.envUint("DEPLOYER_KEY");
    address public deployer = vm.addr(deployerKey);

    function run() public returns (IReceiverCCIP, IRestakingConnector, IAgentFactory) {
        return _run(false);
    }

    function testrun() public returns (IReceiverCCIP, IRestakingConnector, IAgentFactory) {
        vm.deal(deployer, 1 ether);
        return _run(true);
    }

    function _run(bool isTest) internal returns (IReceiverCCIP, IRestakingConnector, IAgentFactory) {

        fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        senderContract = fileReader.readSenderContract();

        (
            strategy,
            strategyManager,
            , // strategyFactory
            , // pauserRegistry
            delegationManager,
            , // _rewardsCoordinator
            // token
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        vm.startBroadcast(deployerKey);

        proxyAdmin = new ProxyAdmin();

        // deploy 6551 Registry
        registry6551 = IERC6551Registry(address(new ERC6551Registry()));
        // deploy 6551 EigenAgentOwner NFT
        eigenAgentOwner721 = IEigenAgentOwner721(
            address(new TransparentUpgradeableProxy(
                address(new EigenAgentOwner721()),
                address(proxyAdmin),
                abi.encodeWithSelector(
                    EigenAgentOwner721.initialize.selector,
                    "EigenAgentOwner",
                    "EAO"
                )
            ))
        );

        agentFactoryProxy = IAgentFactory(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(new AgentFactory(registry6551, eigenAgentOwner721)),
                    address(proxyAdmin),
                    ""
                )
            ))
        );

        // deploy restaking connector for Eigenlayer
        restakingProxy = RestakingConnector(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(new RestakingConnector()),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        RestakingConnector.initialize.selector,
                        agentFactoryProxy
                    )
                )
            ))
        );

        restakingProxy.addAdmin(deployer);
        restakingProxy.setEigenlayerContracts(delegationManager, strategyManager, strategy);
        agentFactoryProxy.addAdmin(deployer);
        agentFactoryProxy.setRestakingConnector(address(restakingProxy));

        // deploy real receiver implementation and upgradeAndCall initializer
        receiverProxy = ReceiverCCIP(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(new ReceiverCCIP(EthSepolia.Router, EthSepolia.Link)),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        ReceiverCCIP.initialize.selector,
                        IRestakingConnector(address(restakingProxy)),
                        senderContract
                    )
                )
            ))
        );

        // Receiver both receives and sends messages back to L2 Sender
        receiverProxy.allowlistSourceChain(EthSepolia.ChainSelector, true);
        receiverProxy.allowlistSourceChain(BaseSepolia.ChainSelector, true);
        receiverProxy.allowlistDestinationChain(BaseSepolia.ChainSelector, true);
        receiverProxy.allowlistDestinationChain(EthSepolia.ChainSelector, true);

        receiverProxy.allowlistSender(address(senderContract), true);
        receiverProxy.setSenderContractL2Addr(address(senderContract));

        eigenAgentOwner721.addAdmin(deployer);
        eigenAgentOwner721.addAdmin(address(restakingProxy));
        eigenAgentOwner721.addToWhitelistedCallers(address(restakingProxy));
        eigenAgentOwner721.setAgentFactory(agentFactoryProxy);

        restakingProxy.setReceiverCCIP(address(receiverProxy));

        // seed the receiver contract with a bit of ETH
        if (address(receiverProxy).balance < 0.02 ether) {
            (bool sent, ) = address(receiverProxy).call{value: 0.05 ether}("");
            require(sent, "Failed to send Ether");
        }

        require(
            address(agentFactoryProxy.getRestakingConnector()) == address(restakingProxy),
            "agentFactoryProxy: did not set a restakingConnector"
        );
        require(
            address(receiverProxy.getRestakingConnector()) == address(restakingProxy),
            "receiverProxy: missing restakingConnector"
        );
        require(
            address(restakingProxy.getAgentFactory()) == address(agentFactoryProxy),
            "restakingConnector: missing AgentFactory"
        );
        require(
            address(restakingProxy.getReceiverCCIP()) == address(receiverProxy),
            "restakingConnector: missing ReceiverCCIP"
        );
        require(
            address(eigenAgentOwner721.getAgentFactory()) == address(agentFactoryProxy),
            "EigenAgentOwner721 NFT: missing AgentFactory"
        );
        require(
            address(agentFactoryProxy.getRestakingConnector()) == address(restakingProxy),
            "agentFactory: missing restakingConnector"
        );

        vm.stopBroadcast();

        if (!isTest) {
            fileReader.saveReceiverBridgeContracts(
                isTest,
                address(receiverProxy),
                address(restakingProxy),
                address(agentFactoryProxy),
                address(registry6551),
                address(eigenAgentOwner721),
                address(proxyAdmin)
            );
        }

        return (
            IReceiverCCIP(address(receiverProxy)),
            IRestakingConnector(address(restakingProxy)),
            IAgentFactory(address(agentFactoryProxy))
        );
    }
}
