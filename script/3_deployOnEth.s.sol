// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, stdJson, console} from "forge-std/Script.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IReceiverCCIP} from "../src/IReceiverCCIP.sol";
import {IRestakingConnector} from "../src/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {DeployOnArbScript} from "./2_deployOnArb.s.sol";
import {FileUtils} from "./FileUtils.sol";


contract DeployOnEthScript is Script {

    RestakingConnector public restakingConnector;
    ReceiverCCIP public receiverContract;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    uint256 public deployerKey;
    address public deployer;

    function run() public returns (IReceiverCCIP, IRestakingConnector) {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        FileUtils fileUtils = new FileUtils();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        (
            IStrategyManager strategyManager,
            IPauserRegistry pauserRegistry,
            IRewardsCoordinator rewardsCoordinator,
            IDelegationManager delegationManager,
            IStrategy strategy
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        vm.startBroadcast(deployerKey);

        address router = address(0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59);
        address link = address(0x779877A7B0D9E8603169DdbD7836e478b4624789);

        // deploy L2 msg decoder for Eigenlayer
        restakingConnector = new RestakingConnector();

        restakingConnector.addAdmin(deployer);

        require(restakingConnector.isAdmin(deployer), "failed to add deployer as admin");

        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

        // deploy receiver contract
        receiverContract = new ReceiverCCIP(router, link, address(restakingConnector));

        uint64 _sourceChainSelector = 3478487238524512106; // Arb Sepolia
        receiverContract.allowlistSourceChain(_sourceChainSelector, true);

        address sender = address(fileUtils.getSenderContract());
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

//////////////////////////////////////////////
// Arb Sepolia
//////////////////////////////////////////////
// Router:
// 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165
//
// chain selector:
// 3478487238524512106
//
// CCIP-BnM token:
// 0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D
//////////////////////////////////////////////

//////////////////////////////////////////////
// ETH Sepolia
//////////////////////////////////////////////
// Router:
// 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59
//
// chain selector:
// 16015286601757825753
//
// CCIP-BnM token:
// 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05
//////////////////////////////////////////////