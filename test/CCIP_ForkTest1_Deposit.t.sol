// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";

import {BaseMessengerCCIP} from "../src/BaseMessengerCCIP.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";
import {EigenlayerMsgDecoders} from "../src/utils/EigenlayerMsgDecoders.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {RouterFees} from "../script/RouterFees.sol";



contract CCIP_ForkTest_Deposit_Tests is BaseTestEnvironment {

    uint256 expiry;
    uint256 amount;

    function setUp() public {
        // setup forked environments for L2 and L1 contracts
        setUpForkedEnvironment();
        // call params
        amount = 0.0028 ether;
        expiry = block.timestamp + 1 hours;
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

    function test_ReceiverL1_CatchDepositError_RefundAfterExpiry() public {

        vm.selectFork(ethForkId);

        uint256 execNonce = 0;
        // should revert with EigenAgentExecutionError(signer, expiry)
        address invalidEigenlayerContract = vm.addr(4444);
        // make expiryShort to test refund on expiry feature
        uint256 expiryShort = block.timestamp + 60 seconds;

        bytes memory messageWithSignature;
        {
            bytes memory depositMessage = encodeDepositIntoStrategyMsg(
                invalidEigenlayerContract,
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
                expiryShort
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
            sender: abi.encode(deployer),
            destTokenAmounts: destTokenAmounts,
            data: abi.encode(string(
                messageWithSignature
            ))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IRestakingConnector.ExecutionErrorRefundAfterExpiry.selector,
                "StrategyManager.onlyStrategiesWhitelistedForDeposit: strategy not whitelisted",
                "Manually execute to refund after timestamp:",
                expiryShort
            )
        );
        receiverContract.mockCCIPReceive(any2EvmMessage);

        // warp ahead past the expiryShort timestamp:
        vm.warp(block.timestamp + 3666); // 1 hour, 1 min, 6 seconds
        vm.roll((block.timestamp + 3666) / 12); // 305 blocks on ETH


        vm.expectEmit(false, true, true, false);
        emit BaseMessengerCCIP.MessageSent(
            bytes32(0x0), // messageId
            BaseSepolia.ChainSelector, // destination chain
            bob, // receiver
            address(tokenL1),
            amount, // amount of tokens to send
            address(0), // 0 for native gas
            0 // fees
        );
        vm.expectEmit(true, true, true, false);
        emit ReceiverCCIP.RefundingDeposit(bob, address(tokenL1), amount);

        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    function test_ReceiverL1_ForceAgentFactoryError_RefundAfterExpiry() public {

        vm.selectFork(ethForkId);

        uint256 execNonce = 0;
        address invalidEigenlayerContract = vm.addr(4444);
        // should revert with EigenAgentExecutionError(signer, expiry)
        uint256 expiryShort = block.timestamp + 60 seconds;
        // make expiryShort to test refund on expiry feature

        bytes memory messageWithSignature;
        {
            bytes memory depositMessage = encodeDepositIntoStrategyMsg(
                invalidEigenlayerContract,
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
                expiryShort
            );
        }

        // warp ahead past the expiryShort timestamp:
        vm.warp(block.timestamp + 3666); // 1 hour, 1 min, 6 seconds
        vm.roll((block.timestamp + 3666) / 12); // 305 blocks on ETH

        // Introduce error: restakingConnector can no longer call agentFactory to
        // get or spawn EigenAgents
        vm.prank(deployer);
        agentFactory.setRestakingConnector(vm.addr(1233));

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1), // CCIP-BnM token address on Eth Sepolia.
            amount: amount
        });
        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0x0),
            sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
            sender: abi.encode(deployer),
            destTokenAmounts: destTokenAmounts,
            data: abi.encode(string(
                messageWithSignature
            ))
        });

        // Call will revert because AgentFactory._restakingConnector is set to a random address:
        // "AgentFactory: not called by RestakingConnector"
        //
        // But as it is after expiry, we instead trigger the refund (emitting an event)
        vm.expectEmit(true, true, true, false);
        emit ReceiverCCIP.RefundingDeposit(bob, address(tokenL1), amount);
        receiverContract.mockCCIPReceive(any2EvmMessage);
    }


    function test_RouterFees_OnL1AndL2() public {

        vm.selectFork(ethForkId);
        RouterFees routerFeesL1 = new RouterFees();

        uint256 fees1 = routerFeesL1.getRouterFeesL1(
            address(receiverContract), // receiver
            string("some random message"), // message
            address(EthSepolia.BridgeToken), // tokenL1
            0.1 ether, // amount
            0 // gasLimit
        );

        require(fees1 > 0, "RouterFees on L1 did not esimate bridging fees");

        vm.selectFork(l2ForkId);
        RouterFees routerFeesL2 = new RouterFees();

        uint256 fees2 = routerFeesL2.getRouterFeesL2(
            address(senderContract), // receiver
            string("some random message"), // message
            address(BaseSepolia.BridgeToken), // tokenL1
            0.1 ether, // amount
            0 // gasLimit
        );

        require(fees2 > 0, "RouterFees on L2 did not esimate bridging fees");
    }
}
