// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";



contract CCIP_ForkTest_QueueWithdrawal_Tests is BaseTestEnvironment {

    uint256 expiry;
    uint256 amount;
    event SetQueueWithdrawalBlock(address indexed, uint256 indexed, uint256 indexed);

    function setUp() public {
        // setup forked environments for L2 and L1 contracts
        setUpForkedEnvironment();
        // call params
        amount = 0.0028 ether;
        expiry = block.timestamp + 1 days;
    }

    /*
     *
     *
     *             Setup Eigenlayer State for QueueWithdrawals
     *
     *
     */

    function setupL1State_Deposit() public {

        ///////////////////////////
        //// Setup EigenAgent
        ///////////////////////////
        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);
        {
            // should revert
            vm.expectRevert("AgentFactory: not called by RestakingConnector");
            eigenAgent = agentFactory.tryGetEigenAgentOrSpawn(bob);

            // for testing purposes, spawn eigenAgent with admin
            eigenAgent = agentFactory.getEigenAgent(bob);
            if (address(eigenAgent) == address(0)) {
                eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(bob);
            }
        }
        vm.stopBroadcast();

        ///////////////////////////
        //// Setup Deposit
        ///////////////////////////

        uint256 execNonce0 = eigenAgent.execNonce();

        bytes memory messageWithSignature0;
        {
        bytes memory depositMessage = encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature0 = signMessageForEigenAgentExecution(
                bobKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager), // StrategyManager for deposits
                depositMessage,
                execNonce0,
                expiry
            );
        }

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1), // CCIP-BnM token address on Eth Sepolia.
            amount: amount
        });
        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0x0),
            sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
            sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
            destTokenAmounts: destTokenAmounts, // Tokens and their amounts in their destination chain representation.
            data: abi.encode(string(
                messageWithSignature0
            )) // CCIP abi.encodes a string message when sending
        });

        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_ReceiverL1_MockReceive_QueueWithdrawal() public {

        setupL1State_Deposit();
        uint256 bobBalanceBefore = tokenL1.balanceOf(bob);

        /////////////////////////////////////
        //// Mock message to L1 Receiver
        /////////////////////////////////////

        uint256 execNonce1 = eigenAgent.execNonce();
        bytes memory messageWithSignature1;
        {
            IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
            uint256[] memory sharesToWithdraw = new uint256[](1);
            strategiesToWithdraw[0] = strategy;
            sharesToWithdraw[0] = amount;

            IDelegationManager.QueuedWithdrawalParams[] memory QWPArray;
            QWPArray = new IDelegationManager.QueuedWithdrawalParams[](1);
            QWPArray[0] = IDelegationManager.QueuedWithdrawalParams({
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw,
                withdrawer: address(eigenAgent)
            });

            // create the queueWithdrawal message for Eigenlayer
            bytes memory withdrawalMessage = encodeQueueWithdrawalsMsg(
                QWPArray
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature1 = signMessageForEigenAgentExecution(
                bobKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager),
                withdrawalMessage,
                execNonce1,
                expiry
            );
        }

        Client.Any2EVMMessage memory any2EvmMessageQueueWithdrawal = Client.Any2EVMMessage({
            messageId: bytes32(uint256(9999)),
            sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
            sender: abi.encode(address(deployer)), // bytes: abi.decode(sender) if coming from an EVM chain.
            destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging coins, just sending msg
            data: abi.encode(string(
                messageWithSignature1
            ))
        });

        uint256 expectedBlock = block.number; // expected block withdrawal was queued
        uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(address(eigenAgent));

        vm.expectEmit(true, true, true, false);
        emit SetQueueWithdrawalBlock(address(eigenAgent), withdrawalNonce, expectedBlock);
        // Dispatch message to L2 receiver -> EigenAgent -> Eigenlayer
        receiverContract.mockCCIPReceive(any2EvmMessageQueueWithdrawal);

        uint256 bobBalanceAfter = tokenL1.balanceOf(bob);
        vm.assertEq(bobBalanceAfter, bobBalanceBefore, "Bob's balance should have stayed the same on L1");

        uint256 withdrawalBlock = restakingConnector.getQueueWithdrawalBlock(address(eigenAgent), withdrawalNonce);
        vm.assertEq(withdrawalBlock, expectedBlock, "QueueWithdrawalBlock should be saved");

        // there should be 1 queued withdrawal for Bob's EigenAgent
        vm.assertEq(1, delegationManager.cumulativeWithdrawalsQueued(address(eigenAgent)));
    }

    function test_ReceiverL1_CatchError_NullArrayQueueWithdrawal() public {

        setupL1State_Deposit();
        /// Test error handling, but do nothing as no tokens are bridged in queueWithdrawal calls.

        /////////////////////////////////////
        //// Mock message to L1 Receiver
        /////////////////////////////////////

        uint256 execNonce1 = eigenAgent.execNonce();
        uint256 expiryShort = block.timestamp + 60 seconds;
        // make expiryShort to test refund on expiry feature

        bytes memory messageWithSignature1;
        {
            // Eigenlayer reverts with zero-length arrays
            IDelegationManager.QueuedWithdrawalParams[] memory QWPArray;
            QWPArray = new IDelegationManager.QueuedWithdrawalParams[](0);

            // create the queueWithdrawal message for Eigenlayer
            bytes memory withdrawalMessage = encodeQueueWithdrawalsMsg(
                QWPArray
            );
            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature1 = signMessageForEigenAgentExecution(
                bobKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager),
                withdrawalMessage,
                execNonce1,
                expiryShort
            );
        }

        Client.Any2EVMMessage memory any2EvmMessageQueueWithdrawal = Client.Any2EVMMessage({
            messageId: bytes32(uint256(9999)),
            sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
            sender: abi.encode(address(deployer)), // bytes: abi.decode(sender) if coming from an EVM chain.
            destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging coins, just sending msg
            data: abi.encode(string(
                messageWithSignature1
            ))
        });

        // revert(abi.decode(customError, (string)));
        vm.expectRevert();
        receiverContract.mockCCIPReceive(any2EvmMessageQueueWithdrawal);
    }

}
