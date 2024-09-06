// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";

import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";



contract CCIP_ForkTest_QueueWithdrawal_Tests is BaseTestEnvironment {

    uint256 expiry;
    uint256 amount;

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
     *             Tests
     *
     *
     */

    function test_CCIP_Eigenlayer_QueueWithdrawal6551() public {

        //////////////////////////////////////////////////////
        /// L1: ReceiverCCIP -> EigenAgent -> Eigenlayer
        //////////////////////////////////////////////////////
        vm.selectFork(ethForkId);
        IEigenAgent6551 eigenAgent;

        vm.startBroadcast(deployerKey);
        // should revert
        vm.expectRevert("not called by RestakingConnector");
        eigenAgent = agentFactory.tryGetEigenAgentOrSpawn(bob);

        // for testing purposes, spawn eigenAgent with admin
        eigenAgent = agentFactory.getEigenAgent(bob);
        if (address(eigenAgent) == address(0)) {
            eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(bob);
        }
        console.log("eigenAgent: ", address(eigenAgent));
        console.log("bob: ", address(bob));
        vm.stopBroadcast();

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
            sourceChainSelector: BaseSepolia.ChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
            destTokenAmounts: destTokenAmounts, // Tokens and their amounts in their destination chain representation.
            data: abi.encode(string(
                messageWithSignature0
            )) // CCIP abi.encodes a string message when sending
        });

        receiverContract.mockCCIPReceive(any2EvmMessage);

        /////////////////////////////////////
        //// Mock send message to CCIP -> EigenAgent -> Eigenlayer
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
            sourceChainSelector: BaseSepolia.ChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(address(deployer)), // bytes: abi.decode(sender) if coming from an EVM chain.
            destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging coins, just sending msg
            data: abi.encode(string(
                messageWithSignature1
            ))
        });

        receiverContract.mockCCIPReceive(any2EvmMessageQueueWithdrawal);
    }

}
