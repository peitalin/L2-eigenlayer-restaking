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
import {ClientEncoders} from "./ClientEncoders.sol";


contract CompleteWithdrawalScript is Script, ScriptUtils {

    FileReader public fileReader;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    ClientEncoders public encoders;
    SignatureUtilsEIP1271 public signatureUtils;

    IReceiverCCIP public receiverProxy;
    ISenderCCIP public senderProxy;
    IRestakingConnector public restakingConnector;
    IAgentFactory public agentFactory;
    address public senderAddr;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    IERC20 public token;
    IERC20 public ccipBnM;

    uint256 public deployerKey;
    address public deployer;
    address public staker;
    address public withdrawer;
    uint256 public amount;
    uint256 public expiry;
    uint256 public middlewareTimesIndex; // not used yet, for slashing
    bool public receiveAsTokens;

    address public TARGET_CONTRACT; // Contract that EigenAgent forwards calls to
    uint256 public execNonce; // EigenAgent execution nonce
    IEigenAgent6551 public eigenAgent;

    function run() public {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        bool isTest = block.chainid == 31337;
        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

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

        senderProxy = fileReader.readSenderContract();
        senderAddr = address(senderProxy);

        (receiverProxy, restakingConnector) = fileReader.readReceiverRestakingConnector();
        agentFactory = fileReader.readAgentFactory();

        ccipBnM = IERC20(address(BaseSepolia.BridgeToken)); // BaseSepolia contract
        TARGET_CONTRACT = address(delegationManager);

        /////////////////////////////////////////////////////////////////
        ////// L1: Get Complete Withdrawals Params
        /////////////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        // Get EigenAgent
        eigenAgent = agentFactory.getEigenAgent(deployer);
        if (address(eigenAgent) != address(0)) {
            // if the user already has a EigenAgent, fetch current execution Nonce
            execNonce = eigenAgent.execNonce();
        } else {
            // otherwise agentFactory will spawn one for the user
            // eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);
        }

        amount = 0 ether; // only sending a withdrawal message, not bridging tokens.
        expiry = block.timestamp + 2 hours;
        staker = address(eigenAgent); // this should be EigenAgent (as in StrategyManager)
        withdrawer = address(eigenAgent);

        require(staker == withdrawer, "require: staker == withdrawer");
        require(address(eigenAgent) == withdrawer, "require withdrawer == EigenAgent");

        IDelegationManager.Withdrawal memory withdrawal = fileReader.readWithdrawalInfo(
            staker,
            "script/withdrawals-queued/"
        );

        if (isTest) {
            // mock save a queueWithdrawalBlock
            vm.prank(deployer);
            restakingConnector.setQueueWithdrawalBlock(
                withdrawal.staker,
                withdrawal.nonce,
                111
            );
        }

        // Fetch the correct withdrawal.startBlock and withdrawalRoot
        withdrawal.startBlock = uint32(restakingConnector.getQueueWithdrawalBlock(
            withdrawal.staker,
            withdrawal.nonce
        ));

        bytes32 withdrawalRootCalculated = delegationManager.calculateWithdrawalRoot(withdrawal);

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = withdrawal.strategies[0].underlyingToken();

        /////////////////////////////////////////////////////////////////
        /////// Broadcast to L2
        /////////////////////////////////////////////////////////////////

        vm.selectFork(l2ForkId);
        encoders = new ClientEncoders();
        signatureUtils = new SignatureUtilsEIP1271();

        vm.startBroadcast(deployerKey);

        require(
            senderProxy.allowlistedSenders(address(receiverProxy)),
            "senderCCIP: must allowlistSender(receiverCCIP)"
        );

        middlewareTimesIndex = 0; // not used yet, for slashing
        receiveAsTokens = true;

        bytes memory completeWithdrawalMessage;
        bytes memory messageWithSignature;
        {
            completeWithdrawalMessage = encoders.encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                middlewareTimesIndex,
                receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signatureUtils.signMessageForEigenAgentExecution(
                deployerKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                TARGET_CONTRACT,
                completeWithdrawalMessage,
                execNonce,
                expiry
            );
        }

        topupSenderEthBalance(senderAddr);
        senderProxy.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverProxy),
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
