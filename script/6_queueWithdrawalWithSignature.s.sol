// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";

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


contract QueueWithdrawalWithSignatureScript is Script, ScriptUtils {

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

    function run() public {

        bool isTest = block.chainid == 31337;
        uint256 arbForkId = vm.createFork("arbsepolia");
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

        // First get nonce from Eigenlayer contracts in EthSepolia
        vm.selectFork(ethForkId);

        // TODO: refactor SenderCCIP to allow sending 0 tokens
        amount = 0.00001 ether; // only sending a withdrawal message, not bridging tokens.
        staker = deployer;
        expiry = block.timestamp + 6 hours;

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = strategyManager.stakerStrategyShares(staker, strategy);

        address withdrawer = address(receiverContract);
        uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(staker);
        address delegatedTo = delegationManager.delegatedTo(staker);
        uint32 startBlock = uint32(block.number); // needed to CompleteWithdrawals

        bytes memory signature;
        {
            bytes32 digestHash = signatureUtils.calculateQueueWithdrawalDigestHash(
                staker,
                strategiesToWithdraw,
                sharesToWithdraw,
                nonce,
                expiry,
                address(delegationManager),
                block.chainid
            );

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash);
            signature = abi.encodePacked(r, s, v);

            signatureUtils.checkSignature_EIP1271(staker, digestHash, signature);
        }


        /////////////////////////////////////////////////////////////////
        ////// Setup Queue Withdrawals Params (reads from Eigenlayer contracts on L1)
        /////////////////////////////////////////////////////////////////

        bytes memory message;
        // put the following in separate closure (stack too deep errors)
        {
            IDelegationManager.QueuedWithdrawalWithSignatureParams memory queuedWithdrawalWithSig;
            queuedWithdrawalWithSig = IDelegationManager.QueuedWithdrawalWithSignatureParams({
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw,
                withdrawer: withdrawer,
                staker: staker,
                signature: signature,
                expiry: expiry
            });

            IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalWithSigArray;
            queuedWithdrawalWithSigArray = new IDelegationManager.QueuedWithdrawalWithSignatureParams[](1);
            queuedWithdrawalWithSigArray[0] = queuedWithdrawalWithSig;

            message = eigenlayerMsgEncoders.encodeQueueWithdrawalsWithSignatureMsg(
                queuedWithdrawalWithSigArray
            );
        }

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

        string memory filePath = "script/withdrawals-queued/";
        if (isTest) {
           filePath = "test/withdrawals-queued/";
        }
        // NOTE: Tx will still be bridging so the startBlock = block.number is incorrect.
        // The correct startBlock needs to wait until bridging completes and calls queueWithdrawal on L1.
        // We call getWithdrawalBlock later to get the correct startBlock for calculating withdrawalRoots
        fileReader.saveWithdrawalInfo(
            staker,
            delegatedTo,
            withdrawer,
            nonce,
            0, // startBlock incorrect
            strategiesToWithdraw,
            sharesToWithdraw,
            bytes32(0x0), // withdrawalRoot
            filePath
        );
    }

}
