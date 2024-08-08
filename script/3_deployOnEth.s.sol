// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/IReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {FileReader} from "./Addresses.sol";
import {ArbSepolia, EthSepolia} from "./Addresses.sol";


contract DeployOnEthScript is Script {

    RestakingConnector public restakingConnector;
    ReceiverCCIP public receiverContract;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    uint256 public deployerKey;
    address public deployer;

    function run() public returns (IReceiverCCIP, IRestakingConnector) {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        FileReader fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        (
            IStrategy strategy,
            IStrategyManager strategyManager,
            , // strategyFactory
            , // pauserRegistry
            IDelegationManager delegationManager,
            // rewardsCoordinator
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        // deploy restaking connector for Eigenlayer
        restakingConnector = new RestakingConnector();

        restakingConnector.addAdmin(deployer);
        require(restakingConnector.isAdmin(deployer), "failed to add deployer as admin");

        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

        // deploy receiver contract
        receiverContract = new ReceiverCCIP(EthSepolia.Router, EthSepolia.Link, address(restakingConnector));

        receiverContract.allowlistSourceChain(ArbSepolia.ChainSelector, true);

        address sender = address(fileReader.getSenderContract());
        receiverContract.allowlistSender(sender, true);

        (
            IDelegationManager _d,
            IStrategyManager _sm,
            IStrategy _s
        ) = restakingConnector.getEigenlayerContracts();

        require(address(_d) != address(0), "DelegationManager cannot be address(0)");
        require(address(_sm) != address(0), "StrategyManager cannot be address(0)");
        require(address(_s) != address(0), "Strategy cannot be address(0)");

        vm.stopBroadcast();

        return (
            IReceiverCCIP(address(receiverContract)),
            IRestakingConnector(address(restakingConnector))
        );
    }
}
