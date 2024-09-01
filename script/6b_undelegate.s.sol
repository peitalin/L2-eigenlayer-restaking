// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, stdJson, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";
import {ScriptUtils} from "./ScriptUtils.sol";
import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";

import {ClientSigners} from "./ClientSigners.sol";
import {ClientEncoders} from "./ClientEncoders.sol";


contract UndelegateScript is
    Script,
    ScriptUtils,
    FileReader,
    ClientEncoders,
    ClientSigners
{
    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;

    IStrategy public strategy;
    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IERC20 public tokenL2;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    uint256 public deployerKey;
    address public deployer;
    uint256 public operatorKey;
    address public operator;
    address public staker;
    address public TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

    function run() public {

        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        (
            , // strategy
            strategyManager,
            , // strategyFactory
            , // pauserRegistry
            delegationManager,
            , // _rewardsCoordinator
              // token
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        senderContract = readSenderContract();
        (receiverContract, restakingConnector) = readReceiverRestakingConnector();
        IAgentFactory agentFactory = readAgentFactory();

        tokenL2 = IERC20(address(BaseSepolia.BridgeToken)); // BaseSepolia contract
        TARGET_CONTRACT = address(delegationManager);

        vm.selectFork(ethForkId);

        //////////////////////////////////////////////////////////
        // L1: Register Operator
        //////////////////////////////////////////////////////////

        operatorKey = vm.envUint("OPERATOR_KEY");
        operator = vm.addr(operatorKey);

        require(delegationManager.isOperator(operator), "operator must be registered");

        //// Get User's EigenAgent
        IEigenAgent6551 eigenAgent = agentFactory.getEigenAgent(deployer);
        require(address(eigenAgent) != address(0), "User has no existing EigenAgent");
        require(
            strategyManager.stakerStrategyShares(address(eigenAgent), strategy) >= 0,
            "user's eigenAgent has no deposit in Eigenlayer"
        );

        require(
            delegationManager.delegatedTo(staker) == address(operator),
            "eigenAgent not delegatedTo operator"
        );

        // get EigenAgent's current executionNonce
        uint256 execNonce = eigenAgent.execNonce();
        uint256 sig_expiry = block.timestamp + 2 hours;

        /////////////////////////////////////////////////////////////////
        /////// Broadcast DelegateTo message on L2
        /////////////////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        vm.startBroadcast(deployerKey);

        // Encode undelegate message, and append user signature for EigenAgent execution
        bytes memory messageWithSignature_DT;
        {
            bytes memory delegateToMessage = encodeUndelegateMsg(
                address(eigenAgent)
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_DT = signMessageForEigenAgentExecution(
                deployerKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager), // DelegationManager.delegateTo()
                delegateToMessage,
                execNonce,
                sig_expiry
            );
        }

        topupSenderEthBalance(address(senderContract));

        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_DT),
            address(tokenL2),
            0 // not bridging, just sending message
        );

        vm.stopBroadcast();

    }

}
