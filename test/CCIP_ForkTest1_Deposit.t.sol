// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin-v4-contracts/token/ERC20/IERC20.sol";
import {IPausable} from "@eigenlayer-contracts/interfaces/IPausable.sol";

import {BaseMessengerCCIP} from "../src/BaseMessengerCCIP.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";
import {EigenlayerMsgDecoders} from "../src/utils/EigenlayerMsgDecoders.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {RouterFees} from "../script/RouterFees.sol";
import {console} from "forge-std/console.sol";



contract CCIP_ForkTest_Deposit_Tests is BaseTestEnvironment {

    uint256 expiry;
    uint256 amount;

    error AlreadyRefunded(uint256 amount);

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

        vm.prank(deployer);
        IEigenAgent6551 eigenAgentBob = agentFactory.spawnEigenAgentOnlyOwner(bob);

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
                address(eigenAgentBob),
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
            address agentOwner_,
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

        require(agentOwner_ == bob, "agentOwner incorrect");
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

        uint256 valueOfShares = strategy.userUnderlying(address(eigenAgentBob));
        require(amount == valueOfShares, "valueofShares incorrect");
        require(
            amount == strategyManager.stakerDepositShares(address(eigenAgentBob), strategy),
            "Bob's EigenAgent stakerStrategyShares should equal deposited amount"
        );
    }

    function test_ReceiverL1_CatchDepositError_RefundAfterExpiry() public {

        vm.selectFork(ethForkId);

        uint256 execNonce = 0;
        // should revert with EigenAgentExecutionError(agentOwner, expiry)
        address invalidEigenlayerContract = vm.addr(4444);
        // make expiryShort to test refund on expiry feature
        uint256 expiryShort = block.timestamp + 60 seconds;

        vm.prank(deployer);
        IEigenAgent6551 eigenAgentBob = agentFactory.spawnEigenAgentOnlyOwner(bob);

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
                address(eigenAgentBob),
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
                "StrategyNotWhitelisted()",
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
            destTokenAmounts,
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
        uint256 expiryShort = block.timestamp + 60 seconds;
        bytes32 messageId = bytes32(abi.encode(134));

        // Introduce a different kind of error: RestakingConnector can no longer call agentFactory to
        // get or spawn EigenAgents to test error handling
        vm.prank(deployer);
        agentFactory.setRestakingConnector(vm.addr(1233));

        vm.prank(deployer);
        IEigenAgent6551 eigenAgentBob = agentFactory.spawnEigenAgentOnlyOwner(bob);

        bytes memory messageWithSignature;
        {
            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signMessageForEigenAgentExecution(
                bobKey,
                address(eigenAgentBob),
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager), // StrategyManager to approve + deposit
                encodeDepositIntoStrategyMsg(
                    invalidEigenlayerContract,
                    address(tokenL1),
                    amount
                ),
                execNonce,
                expiryShort
            );
        }

        // warp ahead past the expiryShort timestamp:
        vm.warp(block.timestamp + 2 hours);

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1), // CCIP-BnM token address on Eth Sepolia.
            amount: amount
        });
        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
            sender: abi.encode(address(senderContract)),
            destTokenAmounts: destTokenAmounts,
            data: abi.encode(string(
                messageWithSignature
            ))
        });

        // Call will revert because we're calling an invalid Eigenlayer targetContract:
        // But as it is after expiry, we catch that error and trigger the refund instead (emitting an event)
        vm.expectEmit(true, true, true, false);
        emit ReceiverCCIP.RefundingDeposit(bob, address(tokenL1), amount);
        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    function test_ReceiverL1_PreventRefundAfterManualRefund() public {

        vm.selectFork(ethForkId);

        uint256 execNonce = 0;
        // introduce a permanent error with invalid Eigenlayer contract
        address invalidEigenlayerContract = vm.addr(4444);
        // should revert with EigenAgentExecutionError(agentOwner, expiry)
        uint256 expiryShort = block.timestamp + 60 seconds;
        // make expiryShort to test refund on expiry feature
        bytes32 messageId = bytes32(abi.encode(124));

        vm.prank(deployer);
        IEigenAgent6551 eigenAgentBob = agentFactory.spawnEigenAgentOnlyOwner(bob);

        bytes memory messageWithSignature;
        {
            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signMessageForEigenAgentExecution(
                bobKey,
                address(eigenAgentBob),
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager), // StrategyManager to approve + deposit
                encodeDepositIntoStrategyMsg(
                    invalidEigenlayerContract,
                    address(tokenL1),
                    amount
                ),
                execNonce,
                expiryShort
            );
        }

        // warp ahead past the expiryShort timestamp:
        vm.warp(block.timestamp + 2 hours);

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1), // CCIP-BnM token address on Eth Sepolia.
            amount: amount
        });
        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
            sender: abi.encode(address(senderContract)),
            destTokenAmounts: destTokenAmounts,
            data: abi.encode(string(
                messageWithSignature
            ))
        });

        receiverContract.mockCCIPReceive(any2EvmMessage);

        // attempt to trigger a refund after being manually refunded by admin.
        // Refund is no longer available, should revert with AlreadyRefunded
        vm.expectRevert(abi.encodeWithSelector(
            AlreadyRefunded.selector,
            amount
        ));
        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    function test_RouterFees_OnL1AndL2() public {

        vm.selectFork(ethForkId);
        RouterFees routerFeesL1 = new RouterFees();
        Client.EVMTokenAmount[] memory tokenAmountsL1 = new Client.EVMTokenAmount[](1);
        tokenAmountsL1[0] = Client.EVMTokenAmount({
            token: address(EthSepolia.BridgeToken),
            amount: 0.1 ether
        });

        uint256 fees1 = routerFeesL1.getRouterFeesL1(
            address(receiverContract), // receiver
            string("some random message"), // message
            tokenAmountsL1,
            0 // gasLimit
        );

        require(fees1 > 0, "RouterFees on L1 did not estimate bridging fees");

        vm.selectFork(l2ForkId);
        RouterFees routerFeesL2 = new RouterFees();
        Client.EVMTokenAmount[] memory tokenAmountsL2 = new Client.EVMTokenAmount[](1);
        tokenAmountsL2[0] = Client.EVMTokenAmount({
            token: address(BaseSepolia.BridgeToken),
            amount: 0.1 ether
        });

        uint256 fees2 = routerFeesL2.getRouterFeesL2(
            address(senderContract), // receiver
            string("some random message"), // message
            tokenAmountsL2,
            0 // gasLimit
        );

        require(fees2 > 0, "RouterFees on L2 did not esimate bridging fees");
    }

   /**
     * @notice Test that verifies the token/amount mismatch validation works correctly
     * @dev This test creates a deposit message with a token/amount that doesn't match
     * what's actually being sent in the CCIP message's destTokenAmounts
     */
    function test_ReceiverL1_AmountMismatch_Validation() public {
        vm.selectFork(ethForkId);

        uint256 execNonce = 0;
        uint256 mismatchAmount = amount + 0.001 ether; // Different amount than what's sent

        vm.prank(deployer);
        IEigenAgent6551 eigenAgentBob = agentFactory.spawnEigenAgentOnlyOwner(bob);

        bytes memory messageWithSignature;
        {
            // Create message with a different amount than what's in destTokenAmounts
            bytes memory depositMessage = encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                mismatchAmount // Mismatch amount
            );

            // Sign the message for EigenAgent execution
            messageWithSignature = signMessageForEigenAgentExecution(
                bobKey,
                address(eigenAgentBob),
                block.chainid,
                address(strategyManager),
                depositMessage,
                execNonce,
                expiry
            );
        }

        // Set up CCIP message with a different amount than in the signed message
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1),
            amount: amount // Different from mismatchAmount in the message
        });

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0x0),
            sourceChainSelector: BaseSepolia.ChainSelector,
            sender: abi.encode(deployer),
            destTokenAmounts: destTokenAmounts,
            data: abi.encode(string(messageWithSignature))
        });

        // Expect it to revert with TokenAmountMismatch
        vm.expectRevert(
            abi.encodeWithSelector(
                IRestakingConnector.ExecutionErrorRefundAfterExpiry.selector,
                "Token or amount in message does not match received tokens",
                "Manually execute to refund after timestamp:",
                expiry
            )
        );

        // Attempt to receive the message with mismatched amounts
        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    /**
     * @notice Test that verifies token mismatch validation works correctly
     * @dev This test creates a deposit message with a different token than what's sent
     */
    function test_ReceiverL1_TokenMismatch_Validation() public {
        vm.selectFork(ethForkId);

        vm.prank(deployer);
        IEigenAgent6551 eigenAgentBob = agentFactory.spawnEigenAgentOnlyOwner(bob);

        // Deploy a different token for mismatch testing
        address differentToken = address(0xDEADBEEF);

        uint256 execNonce = 0;
        bytes memory messageWithSignature;
        {
            // Create message with a different token than what's in destTokenAmounts
            bytes memory depositMessage = encodeDepositIntoStrategyMsg(
                address(strategy),
                differentToken, // Different token address
                amount
            );

            // Sign the message for EigenAgent execution
            messageWithSignature = signMessageForEigenAgentExecution(
                bobKey,
                address(eigenAgentBob),
                block.chainid,
                address(strategyManager),
                depositMessage,
                execNonce,
                expiry
            );
        }

        // Set up CCIP message with a different token than in the signed message
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1), // Different from differentToken in the message
            amount: amount
        });

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0x0),
            sourceChainSelector: BaseSepolia.ChainSelector,
            sender: abi.encode(deployer),
            destTokenAmounts: destTokenAmounts,
            data: abi.encode(string(messageWithSignature))
        });

        // Expect it to revert with TokenAmountMismatch
        vm.expectRevert(
            abi.encodeWithSelector(
                IRestakingConnector.ExecutionErrorRefundAfterExpiry.selector,
                "Token or amount in message does not match received tokens",
                "Manually execute to refund after timestamp:",
                expiry
            )
        );

        // Attempt to receive the message with mismatched token
        receiverContract.mockCCIPReceive(any2EvmMessage);
    }
}
