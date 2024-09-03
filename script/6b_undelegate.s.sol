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


// UX Flow for Delegating, Undelegating, and Re-depositing:
// 1) undelegate
// 2) re-delegateTo another Operator
// 3) re-deposit with completeWithdrawal(receiveAsToken=false)
//
// Then you will be delegated to the new operator. Steps (2) and (3) are interchangeable

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

    uint256 public l2ForkId;
    uint256 public ethForkId;

    uint256 public deployerKey = vm.envUint("DEPLOYER_KEY");
    address public deployer = vm.addr(deployerKey);
    uint256 public operatorKey = vm.envUint("OPERATOR_KEY");
    address public operator = vm.addr(operatorKey);

    address public TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

    function run() public {

        l2ForkId = vm.createFork("basesepolia");
        ethForkId = vm.createSelectFork("ethsepolia");

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

        return _run(false);
    }

    function mockrun() public {

        l2ForkId = vm.createFork("basesepolia");
        ethForkId = vm.createSelectFork("ethsepolia");

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

        //////////////////////////////////////////////////////////
        // L1: Register Operator
        //////////////////////////////////////////////////////////

        if (!delegationManager.isOperator(operator)) {
            vm.startBroadcast(operatorKey);
            IDelegationManager.OperatorDetails memory registeringOperatorDetails =
                IDelegationManager.OperatorDetails({
                    __deprecated_earningsReceiver: vm.addr(0xb0b),
                    delegationApprover: operator,
                    stakerOptOutWindowBlocks: 4
                });

            delegationManager.registerAsOperator(registeringOperatorDetails, "operator 1 metadata");
            vm.stopBroadcast();
        }

        return _run(true);
    }

    function _run(bool isTest) public {

        senderContract = readSenderContract();
        (receiverContract, restakingConnector) = readReceiverRestakingConnector();
        IAgentFactory agentFactory = readAgentFactory();

        tokenL2 = IERC20(address(BaseSepolia.BridgeToken)); // BaseSepolia contract
        TARGET_CONTRACT = address(delegationManager);

        vm.selectFork(ethForkId);

        // Get User's EigenAgent
        IEigenAgent6551 eigenAgent = agentFactory.getEigenAgent(deployer);
        require(address(eigenAgent) != address(0), "User has no existing EigenAgent");
        require(
            strategyManager.stakerStrategyShares(address(eigenAgent), strategy) >= 0,
            "user's eigenAgent has no deposit in Eigenlayer"
        );
        require(delegationManager.isOperator(operator), "operator must be registered");
        require(
            delegationManager.delegatedTo(address(eigenAgent)) == address(operator),
            "eigenAgent not delegatedTo operator"
        );

        ///////////////////////////////////////
        // Valid withdrawalRoots: record the following before sending undelegate message:
        //     delegatedTo
        //     nonce
        //     sharesToWithdraw
        //     strategyToWithdraw
        //     withdrawer
        ///////////////////////////////////////

        uint256 execNonce = eigenAgent.execNonce();
        uint256 sig_expiry = block.timestamp + 2 hours;
        uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(address(eigenAgent));
        address withdrawer = address(eigenAgent);

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);
        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = strategyManager.stakerStrategyShares(withdrawer, strategy);

        /////////////////////////////////////////////////////////////////
        /////// Broadcast Undelegate message on L2
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
            0, // not bridging, just sending message
            0 // use default gasLimit for this function
        );

        vm.stopBroadcast();

        /////////////////////////////////////////////////////////////////
        /////// Save undelegate withdrawal details
        /////////////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        string memory filePath = "script/withdrawals-undelegated/";
        if (isTest) {
           filePath = "test/withdrawals-undelegated/";
        }
        // NOTE: Tx will still be bridging after this script runs.
        // startBlock is saved after bridging completes and calls queueWithdrawal on L1.
        // We must call getWithdrawalBlock for the correct startBlock to calculate withdrawalRoots
        saveWithdrawalInfo(
            address(eigenAgent), // staker
            delegationManager.delegatedTo(address(eigenAgent)),
            withdrawer,
            withdrawalNonce,
            0, // startBlock is created later in Eigenlayer
            strategiesToWithdraw,
            sharesToWithdraw,
            bytes32(0x0), // withdrawalRoot is created later (requires startBlock)
            bytes32(0x0), // withdrawalAgenOwnerRoot not used in delegations
            filePath
        );
    }
}
