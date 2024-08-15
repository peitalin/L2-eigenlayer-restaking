// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

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

        address sender = address(fileReader.getSenderContract());

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

        // deploy restaking connector for Eigenlayer
        restakingConnector = new RestakingConnector();
        restakingConnector.addAdmin(deployer);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

        // deploy receiver contract
        receiverContract = new ReceiverCCIP(EthSepolia.Router, EthSepolia.Link, address(restakingConnector));
        receiverContract.allowlistSourceChain(ArbSepolia.ChainSelector, true);
        receiverContract.allowlistSender(sender, true);
        receiverContract.allowlistDestinationChain(ArbSepolia.ChainSelector, true);
        receiverContract.setSenderContractL2Addr(sender);

        // seed the receiver contract with a bit of ETH
        if (address(receiverContract).balance < 0.02 ether) {
            (bool sent, ) = address(receiverContract).call{value: 0.05 ether}("");
            require(sent, "Failed to send Ether");
        }

        vm.stopBroadcast();

        return (
            IReceiverCCIP(address(receiverContract)),
            IRestakingConnector(address(restakingConnector))
        );
    }
}
