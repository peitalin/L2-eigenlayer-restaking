// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {BaseMessengerCCIP} from "../src/BaseMessengerCCIP.sol";
import {EigenlayerMsgDecoders} from "../src/utils/EigenlayerMsgDecoders.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";


contract CCIP_ForkTest_Deposit_Tests is BaseTestEnvironment {

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

    function test_ReceiverL1_MockReceive_DepositIntoStrategy() public {

        /////////////////////////////////////
        //// L1: Mock receiver Deposit message on L1
        /////////////////////////////////////
        vm.selectFork(ethForkId);

        uint256 execNonce = 0;
        bytes memory messageWithSignature;
        {
            bytes memory depositMessage = encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signMessageForEigenAgentExecution(
                bobKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager), // StrategyManager to approve + deposit
                depositMessage,
                execNonce,
                expiry
            );
        }

        EigenlayerMsgDecoders decoders = new EigenlayerMsgDecoders();
        (
            address strategy_,
            address token_,
            uint256 amount_,
            address signer_,
            uint256 expiry_,
            bytes memory signature_
        ) = decoders.decodeDepositIntoStrategyMsg(
            abi.encode(string(
                messageWithSignature
            ))
        );

        require(address(strategy_) == address(strategy), "strategy incorrect");
        require(token_ == address(tokenL1), "token incorrect");
        require(amount_ == amount, "amount incorrect");

        require(signer_ == bob, "signer incorrect");
        require(expiry_ == expiry, "expiry incorrect");
        require(signature_.length == 65, "signature length incorrect");

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
                messageWithSignature
            )) // CCIP abi.encodes a string message when sending
        });

        // mock receiving CCIP message from L2
        receiverContract.mockCCIPReceive(any2EvmMessage);

        IEigenAgent6551 eigenAgent = agentFactory.getEigenAgent(bob);

        uint256 valueOfShares = strategy.userUnderlying(address(eigenAgent));
        require(amount == valueOfShares, "valueofShares incorrect");
        require(
            amount == strategyManager.stakerStrategyShares(address(eigenAgent), strategy),
            "Bob's EigenAgent stakerStrategyShares should equal deposited amount"
        );
    }


    function test_SenderL2_SendMessagePayNative_Deposit() public {

        ///////////////////////////////////////////////////
        //// Setup Sender contracts on L2 fork
        ///////////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        uint256 execNonce = 0;
        bytes memory messageWithSignature;
        {
            bytes memory depositMessage = encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signMessageForEigenAgentExecution(
                bobKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager), // StrategyManager to approve + deposit
                depositMessage,
                execNonce,
                expiry
            );
        }

        // messageId (topic[1]): false as we don't know messageId yet
        vm.expectEmit(false, true, false, false);
        emit BaseMessengerCCIP.MessageSent(
            bytes32(0x0),
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            "dispatched call", // default message
            address(BaseSepolia.BridgeToken), // token to send
            0.1 ether,
            address(0), // native gas for fees
            0
        );
        // event MessageSent(
        //     bytes32 indexed messageId,
        //     uint64 indexed destinationChainSelector,
        //     address receiver,
        //     string text,
        //     address token,
        //     uint256 tokenAmount,
        //     address feeToken,
        //     uint256 fees
        // );
        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature),
            address(BaseSepolia.BridgeToken), // token to send
            0.1 ether, // test sending 0.1e18 tokens
            999_000 // use custom gasLimit for this function
        );
    }

    function test_ReceiverL2_SenderMessagePayNative_TransferToAgentOwner() public {

        ///////////////////////////////////////////////////
        //// Receiver contracts on L1 fork
        ///////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        bytes memory messageWithSignature;
        {
            uint256 execNonce = 0;
            bytes32 mockWithdrawalAgentOwnerRoot = bytes32(abi.encode(123));

            bytes memory message = encodeHandleTransferToAgentOwnerMsg(
                mockWithdrawalAgentOwnerRoot
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signMessageForEigenAgentExecution(
                bobKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager), // StrategyManager to approve + deposit
                message,
                execNonce,
                expiry
            );
        }

        // messageId (topic[1]): false as we don't know messageId yet
        vm.expectEmit(false, true, false, false);
        emit BaseMessengerCCIP.MessageSent(
            bytes32(0x0),
            BaseSepolia.ChainSelector, // destination chain
            address(senderContract),
            "dispatched call", // default message
            address(EthSepolia.BridgeToken), // token to send
            0 ether,
            address(0), // native gas for fees
            0
        );
        // event MessageSent(
        //     bytes32 indexed messageId,
        //     uint64 indexed destinationChainSelector,
        //     address receiver,
        //     string text,
        //     address token,
        //     uint256 tokenAmount,
        //     address feeToken,
        //     uint256 fees
        // );
        receiverContract.sendMessagePayNative(
            BaseSepolia.ChainSelector, // destination chain
            address(senderContract),
            string(messageWithSignature),
            address(EthSepolia.BridgeToken), // token to send
            0 ether, // test sending 0 tokens
            888_000 // use custom gasLimit for this function
        );

        vm.expectEmit(false, true, false, false);
        emit BaseMessengerCCIP.MessageSent(
            bytes32(0x0),
            BaseSepolia.ChainSelector, // destination chain
            address(senderContract),
            "dispatched call", // default message
            address(EthSepolia.BridgeToken), // token to send
            1 ether,
            address(0), // native gas for fees
            0
        );
        receiverContract.sendMessagePayNative(
            BaseSepolia.ChainSelector, // destination chain
            address(senderContract),
            string(messageWithSignature),
            address(EthSepolia.BridgeToken), // token to send
            1 ether, // test sending 1e18 tokens
            888_000 // use custom gasLimit for this function
        );
    }

}
