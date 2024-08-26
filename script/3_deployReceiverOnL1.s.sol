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

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ERC6551Registry} from "@6551/ERC6551Registry.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
// import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
// import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";



contract DeployReceiverOnL1Script is Script {

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

        ISenderCCIP senderContract = fileReader.readSenderContract();

        (
            IStrategy strategy,
            IStrategyManager strategyManager,
            , // strategyFactory
            , // pauserRegistry
            IDelegationManager delegationManager,
            , // _rewardsCoordinator
            // token
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        vm.startBroadcast(deployerKey);

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        // deploy restaking connector for Eigenlayer
        RestakingConnector restakingConnectorImpl = new RestakingConnector();
        restakingConnector = RestakingConnector(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(restakingConnectorImpl),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        RestakingConnector.initialize.selector
                    )
                )
            ))
        );
        restakingConnector.addAdmin(deployer);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

        // deploy 6551 Registry
        ERC6551Registry registry6551 = new ERC6551Registry();
        // deploy 6551 EigenAgentOwner NFT
        EigenAgentOwner721 eigenAgentOwner721 = EigenAgentOwner721(
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
                        senderContract,
                        registry6551,
                        eigenAgentOwner721
                    )
                )
            ))
        );

        receiverProxy.allowlistSourceChain(BaseSepolia.ChainSelector, true);
        receiverProxy.allowlistDestinationChain(BaseSepolia.ChainSelector, true);
        receiverProxy.allowlistSender(address(senderContract), true);
        receiverProxy.setSenderContractL2Addr(address(senderContract));

        eigenAgentOwner721.addAdmin(deployer);
        eigenAgentOwner721.addAdmin(address(receiverProxy));
        eigenAgentOwner721.setReceiverContract(IReceiverCCIP(address(receiverProxy)));

        restakingConnector.addAdmin(address(receiverProxy));

        // seed the receiver contract with a bit of ETH
        if (address(receiverProxy).balance < 0.02 ether) {
            (bool sent, ) = address(receiverProxy).call{value: 0.05 ether}("");
            require(sent, "Failed to send Ether");
        }

        vm.stopBroadcast();

        fileReader.saveReceiverBridgeContracts(
            address(receiverProxy),
            address(restakingConnector),
            address(registry6551),
            address(eigenAgentOwner721),
            address(proxyAdmin)
        );

        return (
            IReceiverCCIP(address(receiverProxy)),
            IRestakingConnector(address(restakingConnector))
        );
    }
}
