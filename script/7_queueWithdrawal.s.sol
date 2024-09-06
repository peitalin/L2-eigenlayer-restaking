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

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";
import {ScriptUtils} from "./ScriptUtils.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {ClientSigners} from "./ClientSigners.sol";
import {ClientEncoders} from "./ClientEncoders.sol";


contract QueueWithdrawalScript is
    Script,
    ScriptUtils,
    FileReader,
    ClientEncoders,
    ClientSigners
{

    FileReader public fileReader;
    DeployReceiverOnL1Script public deployReceiverOnL1Script;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    IAgentFactory public agentFactory;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    IERC20 public tokenL2;

    address public staker;
    address public withdrawer;
    uint256 public amount;
    uint256 public expiry;
    uint256 public execNonce; // EigenAgent execution nonce
    uint256 public withdrawalNonce; // Eigenlayer withdrawal nonce
    IEigenAgent6551 public eigenAgent;
    address public TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

    function run() public {
        return _run(false);
    }

    function mockrun() public {
        return _run(true);
    }

    function _run(bool isTest) private {

        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

        fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
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

        if (isTest) {
            // if isTest, deploy SenderCCIP and ReceiverCCIP again
            // or it will read stale deployed versions because of forkSelect
            vm.selectFork(ethForkId);
            (
                receiverContract,
                restakingConnector,
                agentFactory
            ) = deployReceiverOnL1Script.mockrun();

            vm.selectFork(l2ForkId);
            // mock deploy on L2 Fork
            DeploySenderOnL2Script deployOnL2Script = new DeploySenderOnL2Script();
            (senderContract,) = deployOnL2Script.mockrun();

            // go back to ETH fork
            vm.selectFork(ethForkId);

        } else {
            // otherwise if running the script, read the existing contracts on Sepolia
            senderContract = readSenderContract();
            (
                receiverContract,
                restakingConnector
            ) = readReceiverRestakingConnector();

            agentFactory = readAgentFactory();
        }

        eigenAgent = agentFactory.getEigenAgent(deployer);
        if (address(eigenAgent) == address(0)) {
            // revert("User must have existing deposit in Eigenlayer + EigenAgent");
            vm.prank(deployer);
            eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);
            execNonce = 0;
        } else {
            execNonce = eigenAgent.execNonce();
        }

        ////////////////////////////////////////////////////////////
        // Parameters
        ////////////////////////////////////////////////////////////

        tokenL2 = IERC20(address(BaseSepolia.BridgeToken)); // BaseSepolia contract
        TARGET_CONTRACT = address(delegationManager);

        // only sending a withdrawal message, not bridging tokens.
        amount = 0 ether;
        expiry = block.timestamp + 2 hours;
        staker = address(eigenAgent);
        withdrawer = address(eigenAgent);
        // staker == withdrawer == msg.sender in StrategyManager, which is EigenAgent
        require(staker == withdrawer, "require: staker == withdrawer");
        require(address(eigenAgent) == withdrawer, "require withdrawer == EigenAgent");

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = strategyManager.stakerStrategyShares(withdrawer, strategy);

        withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(withdrawer);
        address delegatedTo = delegationManager.delegatedTo(withdrawer);

        console.log("staker (eigenAgent):", staker);
        console.log("withdrawer (eigenAgent):", withdrawer);
        console.log("sharesToWithdraw:", sharesToWithdraw[0]);

        /////////////////////////////////////////////////////////////////
        ////// Sign the queueWithdrawal payload for EigenAgent
        /////////////////////////////////////////////////////////////////

        vm.selectFork(l2ForkId);

        vm.startBroadcast(deployerKey);

        bytes memory withdrawalMessage;
        bytes memory messageWithSignature;

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
        withdrawalMessage = encodeQueueWithdrawalsMsg(queuedWithdrawalArray);

        // sign the message for EigenAgent to execute Eigenlayer command
        messageWithSignature = signMessageForEigenAgentExecution(
            deployerKey,
            EthSepolia.ChainId, // destination chainid where EigenAgent lives
            TARGET_CONTRACT,
            withdrawalMessage,
            execNonce,
            expiry
        );

        /////////////////////////////////////////////////////////////////
        /////// Broadcast to L2
        /////////////////////////////////////////////////////////////////

        topupSenderEthBalance(address(senderContract), isTest);

        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature),
            address(tokenL2),
            amount,
            0 // use default gasLimit for this function
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
        saveWithdrawalInfo(
            staker,
            delegatedTo,
            withdrawer,
            withdrawalNonce,
            0, // startBlock is created later in Eigenlayer
            strategiesToWithdraw,
            sharesToWithdraw,
            bytes32(0x0), // withdrawalRoot is created later when completeWithdrawal
            bytes32(0x0), // withdrawalTransferRoot is created later
            filePath
        );
    }

}
