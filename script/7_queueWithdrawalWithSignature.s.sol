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
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {WhitelistCCIPContractsScript} from "../script/4_whitelistCCIPContracts.s.sol";

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";
import {ScriptUtils} from "./ScriptUtils.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";


contract QueueWithdrawalWithSignatureScript is Script, ScriptUtils {

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
    uint256 public execNonce; // EigenAgent execution nonce
    uint256 public withdrawalNonce; // Eigenlayer withdrawal nonce
    IEigenAgent6551 public eigenAgent;
    address public TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

    function run() public {

        bool isTest = block.chainid == 31337;
        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        signatureUtils = new SignatureUtilsEIP1271(); // needs ethForkId to call getDomainSeparator
        fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        DeployReceiverOnL1Script deployReceiverOnL1Script = new DeployReceiverOnL1Script();

        (
            strategy,
            strategyManager,
            , // strategyFactory
            , // pauserRegistry
            delegationManager,
            , // _rewardsCoordinator
            // token
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        if (isTest) {
            // if isTest, deploy SenderCCIP and ReceiverCCIP again to get the latest version
            // or you will read the stale versions because of forkSelect
            vm.selectFork(ethForkId);
            (
                receiverContract,
                restakingConnector,
                agentFactory
            ) = deployReceiverOnL1Script.testrun();

            vm.selectFork(l2ForkId);
            DeploySenderOnL2Script deployOnL2Script = new DeploySenderOnL2Script();
            senderContract = deployOnL2Script.testrun();

            // go back to ETH fork
            vm.selectFork(ethForkId);

        } else {
            // otherwise if running the script, read the existing contracts on Sepolia
            senderContract = fileReader.readSenderContract();
            (
                receiverContract,
                restakingConnector
            ) = fileReader.readReceiverRestakingConnector();
            agentFactory = fileReader.readAgentFactory();

        }

        eigenAgent = agentFactory.getEigenAgent(deployer);
        if (address(eigenAgent) == address(0)) {
            // revert("User must have existing deposit in Eigenlayer + EigenAgent");
            vm.prank(deployer);
            eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);
            execNonce = 0;
        } else {
            execNonce = eigenAgent.getExecNonce();
        }

        ////////////////////////////////////////////////////////////
        // Parameters
        ////////////////////////////////////////////////////////////

        senderAddr = address(senderContract);
        ccipBnM = IERC20(address(BaseSepolia.CcipBnM)); // BaseSepolia contract
        TARGET_CONTRACT = address(delegationManager);

        // only sending a withdrawal message, not bridging tokens.
        amount = 0 ether;
        expiry = block.timestamp + 2 hours;
        // original staker, not EigenAgent
        staker = eigenAgent.getAgentOwner();
        // withdrawer is EigenAgent
        withdrawer = address(eigenAgent);

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = strategyManager.stakerStrategyShares(withdrawer, strategy);

        withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(withdrawer);
        address delegatedTo = delegationManager.delegatedTo(withdrawer);

        console.log("staker (agentOwner):", staker);
        console.log("withdrawer (eigenAgent):", withdrawer);
        console.log("sharesToWithdraw:", sharesToWithdraw[0]);

        /////////////////////////////////////////////////////////////////
        ////// Sign the queueWithdrawal payload for EigenAgent
        /////////////////////////////////////////////////////////////////

        bytes memory withdrawalMessage;
        bytes memory messageWithSignature;
        {
            IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal;
            queuedWithdrawal = IDelegationManager.QueuedWithdrawalParams({
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw,
                withdrawer: withdrawer
            });
            IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalArray;
            queuedWithdrawalArray = new IDelegationManager.QueuedWithdrawalParams[](1);
            queuedWithdrawalArray[0] = queuedWithdrawal;

            // create the queueWithdrawal message for Eigenlayer
            withdrawalMessage = EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(
                queuedWithdrawalArray
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signatureUtils.signMessageForEigenAgentExecution(
                deployerKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                TARGET_CONTRACT,
                withdrawalMessage,
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

        string memory filePath = "script/withdrawals-queued/";
        if (isTest) {
           filePath = "test/withdrawals-queued/";
        }
        // NOTE: Tx will still be bridging after this script runs.
        // startBlock is saved after bridging completes and calls queueWithdrawal on L1.
        // Then we call getWithdrawalBlock for the correct startBlock to calculate withdrawalRoots
        fileReader.saveWithdrawalInfo(
            staker,
            delegatedTo,
            withdrawer,
            withdrawalNonce,
            0, // startBlock is created later
            strategiesToWithdraw,
            sharesToWithdraw,
            bytes32(0x0), // withdrawalRoot is created later
            filePath
        );
    }

}
