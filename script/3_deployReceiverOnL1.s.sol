// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-v5-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {IReceiverCCIPMock, ReceiverCCIPMock} from "../test/mocks/ReceiverCCIPMock.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {FileReader} from "./FileReader.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";

import {AgentFactory} from "../src/6551/AgentFactory.sol";
import {ERC6551Registry} from "@6551/ERC6551Registry.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";



contract DeployReceiverOnL1Script is Script, FileReader {

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    RestakingConnector public restakingProxy;
    ReceiverCCIP public receiverProxy;
    ISenderCCIP public senderContract;
    IERC6551Registry public registry6551;
    IEigenAgentOwner721 public eigenAgentOwner721;
    IAgentFactory public agentFactoryProxy;

    IStrategy public strategy;
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IRewardsCoordinator public rewardsCoordinator;

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    function run() public returns (IReceiverCCIP, IRestakingConnector, IAgentFactory) {
        return _run(false);
    }

    function mockrun() public returns (IReceiverCCIPMock, IRestakingConnector, IAgentFactory) {

        vm.deal(deployer, 1 ether);

        (
            IReceiverCCIP _receiverProxy,
            IRestakingConnector _restakingConnectorProxy,
            IAgentFactory _agentFactoryProxy
        ) = _run(true);

        return (
            IReceiverCCIPMock(address(_receiverProxy)),
            _restakingConnectorProxy,
            _agentFactoryProxy
        );
    }

    function _run(bool isMockRun) private returns (IReceiverCCIP, IRestakingConnector, IAgentFactory) {

        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        DeployMockEigenlayerContractsScript.EigenlayerAddresses memory ea =
            deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        strategy = ea.strategy;
        strategyManager = ea.strategyManager;
        delegationManager = ea.delegationManager;
        rewardsCoordinator = ea.rewardsCoordinator;

        senderContract = readSenderContract();

        ////////////////////////////////////////////////////////////
        // begin broadcast
        ////////////////////////////////////////////////////////////

        vm.startBroadcast(deployerKey);

        registry6551 = IERC6551Registry(address(new ERC6551Registry()));
        // if (isMockRun) {
        //     // deploy 6551 Registry -- only for testing
        //     registry6551 = IERC6551Registry(address(new ERC6551Registry()));
        // } else {
        //     // on mainnet use the proper registry
        //     // https://holesky.etherscan.io/address/0x000000006551c19487814612e58FE06813775758#code
        //     registry6551 = IERC6551Registry(address(0x000000006551c19487814612e58FE06813775758));
        // }

        // deploy 6551 EigenAgentOwner NFT
        eigenAgentOwner721 = IEigenAgentOwner721(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(new EigenAgentOwner721()),
                    address(deployer),
                    abi.encodeWithSelector(
                        EigenAgentOwner721.initialize.selector,
                        "EigenAgentOwner",
                        "EAO"
                    )
                )
            ))
        );

        // base EigenAgent implementation to spawn clones
        EigenAgent6551 baseEigenAgent = new EigenAgent6551();

        agentFactoryProxy = IAgentFactory(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(new AgentFactory()),
                    address(deployer),
                    abi.encodeWithSelector(
                        AgentFactory.initialize.selector,
                        registry6551,
                        eigenAgentOwner721,
                        baseEigenAgent
                    )
                )
            ))
        );

        // deploy restaking connector for Eigenlayer
        restakingProxy = RestakingConnector(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(new RestakingConnector()),
                    address(deployer),
                    abi.encodeWithSelector(
                        RestakingConnector.initialize.selector,
                        agentFactoryProxy,
                        EthSepolia.BridgeToken,
                        BaseSepolia.BridgeToken
                    )
                )
            ))
        );

        restakingProxy.addAdmin(deployer);
        restakingProxy.setEigenlayerContracts(delegationManager, strategyManager, rewardsCoordinator);
        agentFactoryProxy.addAdmin(deployer);
        agentFactoryProxy.setRestakingConnector(address(restakingProxy));
        // doesn't strictly need to be set, as AgentFactory clones the baseEigenAgent, but good to have.
        baseEigenAgent.setInitialRestakingConnector(address(restakingProxy));

        // deploy real receiver implementation and upgradeAndCall initializer
        ReceiverCCIP receiverImpl;
        if (isMockRun) {
            receiverImpl = new ReceiverCCIPMock(EthSepolia.Router);
        } else {
            receiverImpl = new ReceiverCCIP(EthSepolia.Router);
        }
        receiverProxy = ReceiverCCIP(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(receiverImpl),
                    address(deployer),
                    abi.encodeWithSelector(
                        ReceiverCCIP.initialize.selector,
                        IRestakingConnector(address(restakingProxy)),
                        senderContract
                    )
                )
            ))
        );

        // Receiver both receives and sends messages back to L2 Sender
        receiverProxy.allowlistSourceChain(BaseSepolia.ChainSelector, true);
        receiverProxy.allowlistDestinationChain(BaseSepolia.ChainSelector, true);

        receiverProxy.allowlistSender(BaseSepolia.ChainSelector, address(senderContract), true);
        receiverProxy.setSenderContractL2(address(senderContract));

        eigenAgentOwner721.addAdmin(deployer);
        eigenAgentOwner721.addAdmin(address(restakingProxy));
        eigenAgentOwner721.addToWhitelistedCallers(address(restakingProxy));
        eigenAgentOwner721.setAgentFactory(agentFactoryProxy);
        eigenAgentOwner721.setRewardsCoordinator(rewardsCoordinator);

        restakingProxy.setReceiverCCIP(address(receiverProxy));

        // seed the receiver contract with a bit of ETH
        if (address(receiverProxy).balance < 0.01 ether) {
            (bool sent, ) = address(receiverProxy).call{value: 0.02 ether}("");
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
            address(eigenAgentOwner721.getRewardsCoordinator()) == address(rewardsCoordinator),
            "EigenAgentOwner721 NFT: missing RewardsCoordinator"
        );
        require(
            address(agentFactoryProxy.getRestakingConnector()) == address(restakingProxy),
            "agentFactory: missing restakingConnector"
        );
        require(
            address(agentFactoryProxy.erc6551Registry()) == address(registry6551),
            "agentFactory: missing erc6551registry"
        );
        require(
            address(agentFactoryProxy.baseEigenAgent()) == address(baseEigenAgent),
            "agentFactory: missing baseEigenAgent"
        );

        vm.stopBroadcast();

        if (!isMockRun) {
            saveReceiverBridgeContracts(
                address(receiverProxy),
                address(restakingProxy),
                address(agentFactoryProxy),
                address(registry6551),
                address(eigenAgentOwner721),
                address(baseEigenAgent),
                FILEPATH_BRIDGE_CONTRACTS_L1
            );
        }

        return (
            IReceiverCCIP(address(receiverProxy)),
            IRestakingConnector(address(restakingProxy)),
            IAgentFactory(address(agentFactoryProxy))
        );
    }
}
