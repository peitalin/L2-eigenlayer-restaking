// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, stdJson, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {FileReader, ArbSepolia, EthSepolia} from "./Addresses.sol";
import {ScriptUtils} from "./ScriptUtils.sol";
import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";


contract CompleteWithdrawalScript is Script, ScriptUtils {

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    address public senderAddr;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    IERC20 public token;
    IERC20 public ccipBnM;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    FileReader public fileReader; // keep outside vm.startBroadcast() to avoid deploying
    SignatureUtilsEIP1271 public signatureUtils;
    EigenlayerMsgEncoders public eigenlayerMsgEncoders;

    uint256 public deployerKey;
    address public deployer;
    address public staker;
    uint256 public amount;
    uint256 public expiry;
    uint256 public middlewareTimesIndex; // not used yet, for slashing
    bool public receiveAsTokens;

    function run() public {

        bool isTest = block.chainid == 31337;
        uint256 arbForkId = vm.createFork("arbsepolia");
        // uint256 arbForkId = vm.createSelectFork("arbsepolia");
        // vm.rollFork(71584765); // roll back before CCIP network entered "cursed" state
        uint256 ethForkId = vm.createSelectFork("ethsepolia");
        console.log("arbForkId:", arbForkId);
        console.log("ethForkId:", ethForkId);
        console.log("block.chainid", block.chainid);

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        signatureUtils = new SignatureUtilsEIP1271(); // needs ethForkId to call getDomainSeparator
        eigenlayerMsgEncoders = new EigenlayerMsgEncoders(); // needs ethForkId to call encodeDeposit
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

        senderContract = fileReader.getSenderContract();
        senderAddr = address(senderContract);

        (receiverContract, restakingConnector) = fileReader.getReceiverRestakingConnectorContracts();

        ccipBnM = IERC20(address(ArbSepolia.CcipBnM)); // ArbSepolia contract

        //////////////////////////////////////////////////////////
        /// Create message and signature
        /// In production this is done on the client/frontend
        //////////////////////////////////////////////////////////

        vm.selectFork(ethForkId);

        amount = 0 ether; // only sending a withdrawal message, not bridging tokens.
        staker = deployer;
        expiry = block.timestamp + 6 hours;

        IDelegationManager.Withdrawal memory withdrawal = fileReader.readWithdrawalInfo(
            staker,
            "script/withdrawals-queued/"
        );

        if (isTest) {
            // mock save a queueWithdrawalBloc
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

        // send CCIP message to CompleteWithdrawal
        bytes memory message = eigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
            withdrawal,
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );

        /////////////////////////////////////////////////////////////////
        /////// Broadcast to Arb L2
        /////////////////////////////////////////////////////////////////

        vm.selectFork(arbForkId);
        vm.startBroadcast(deployerKey);

        topupSenderEthBalance(senderAddr);
        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(message),
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
