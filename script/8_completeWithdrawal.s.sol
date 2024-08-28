// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";
import {ScriptUtils} from "./ScriptUtils.sol";
import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";


contract CompleteWithdrawalScript is Script, ScriptUtils {

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    IAgentFactory public agentFactory;
    address public senderAddr;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    IERC20 public token;
    IERC20 public ccipBnM;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    FileReader public fileReader; // keep outside vm.startBroadcast() to avoid deploying
    SignatureUtilsEIP1271 public signatureUtils;

    uint256 public deployerKey;
    address public deployer;
    address public staker;
    address public withdrawer;
    uint256 public amount;
    uint256 public expiry;
    uint256 public middlewareTimesIndex; // not used yet, for slashing
    bool public receiveAsTokens;

    uint256 public execNonce; // EigenAgent execution nonce
    IEigenAgent6551 public eigenAgent;

    function run() public {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        bool isTest = block.chainid == 31337;
        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

        signatureUtils = new SignatureUtilsEIP1271(); // needs ethForkId to call getDomainSeparator
        fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
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

        senderContract = fileReader.readSenderContract();
        senderAddr = address(senderContract);

        (receiverContract, restakingConnector) = fileReader.readReceiverRestakingConnector();
        agentFactory = fileReader.readAgentFactory();

        ccipBnM = IERC20(address(BaseSepolia.CcipBnM)); // BaseSepolia contract

        //////////////////////////////////////////////////////////
        /// Create message and signature
        /// In production this is done on the client/frontend
        //////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        // Get EigenAgent
        eigenAgent = agentFactory.getEigenAgent(deployer);
        execNonce = eigenAgent.getExecNonce();
        if (address(eigenAgent) == address(0)) {
            revert("User must have existing deposit in Eigenlayer + EigenAgent");
        }

        amount = 0 ether; // only sending a withdrawal message, not bridging tokens.
        expiry = block.timestamp + 2 hours;
        staker = deployer;
        withdrawer = address(eigenAgent);

        IDelegationManager.Withdrawal memory withdrawal = fileReader.readWithdrawalInfo(
            staker,
            "script/withdrawals-queued/"
        );

        if (isTest) {
            // mock save a queueWithdrawalBlock
            vm.prank(deployer);
            restakingConnector.setQueueWithdrawalBlock(withdrawal.staker, withdrawal.nonce);
        }

        // Fetch the correct withdrawal.startBlock and withdrawalRoot
        withdrawal.startBlock = uint32(restakingConnector.getQueueWithdrawalBlock(
            withdrawal.staker,
            withdrawal.nonce
        ));

        bytes32 withdrawalRootCalculated = delegationManager.calculateWithdrawalRoot(withdrawal);
        console.log("withdrawalRootCalculated:");
        console.logBytes32(withdrawalRootCalculated);

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = withdrawal.strategies[0].underlyingToken();


        /////////////////////////////////////////////////////////////////
        ////// Setup Complete Withdrawals Params
        /////////////////////////////////////////////////////////////////
        middlewareTimesIndex = 0; // not used yet, for slashing
        receiveAsTokens = true;

        bytes memory completeWithdrawalMessage;
        bytes memory messageWithSignature;
        {
            completeWithdrawalMessage = EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                middlewareTimesIndex,
                receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signatureUtils.signMessageForEigenAgentExecution(
                deployerKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager),
                completeWithdrawalMessage,
                execNonce,
                expiry
            );
        }

        /////////////////////////////////////////////////////////////////
        /////// Broadcast to L2
        /////////////////////////////////////////////////////////////////

        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);

        topupSenderEthBalance(senderAddr);
        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature),
            address(ccipBnM),
            amount
        );

        vm.stopBroadcast();


        vm.selectFork(ethForkId);
        string memory filePath = "script/withdrawals-completed/";
        if (isTest) {
           filePath = "test/withdrawals-completed/";
        }

        fileReader.saveWithdrawalInfo(
            withdrawal.staker,
            withdrawal.delegatedTo,
            withdrawal.withdrawer,
            withdrawal.nonce,
            withdrawal.startBlock,
            withdrawal.strategies,
            withdrawal.shares,
            withdrawalRootCalculated,
            filePath
        );

    }

}
