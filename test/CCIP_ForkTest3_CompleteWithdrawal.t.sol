// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";
import {AgentFactory} from "../src/6551/AgentFactory.sol";



contract CCIP_ForkTest_CompleteWithdrawal_Tests is BaseTestEnvironment {

    uint256 expiry;
    uint256 balanceOfReceiverBefore;
    uint256 balanceOfEigenAgent;

    // SenderHooks.WithdrawalTransferRootCommitted
    event WithdrawalTransferRootCommitted(
        bytes32 indexed, // withdrawalTransferRoot
        address indexed, //  withdrawer (eigenAgent)
        uint256, // amount
        address  // signer (agentOwner)
    );

    function setUp() public {
        // setup forked environments for L2 and L1 contracts
        setUpForkedEnvironment();
        // call params
        expiry = block.timestamp + 1 days;
    }

    /*
     *
     *
     *             Setup Eigenlayer State for CompleteWithdrawals
     *
     *
     */

    function setupL1State_DepositAndQueueWithdrawal(uint256 amount) public {

        vm.assume(amount <= 1 ether);
        vm.assume(amount > 0);

        //////////////////////////////////////////////////////
        /// L1: ReceiverCCIP -> EigenAgent -> Eigenlayer
        //////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        eigenAgent = agentFactory.getEigenAgent(bob); // should not exist yet
        require(address(eigenAgent) == address(0), "test assumes no EigenAgent yet");

        console.log("bob address:", bob);
        console.log("eigenAgent:", address(eigenAgent));
        console.log("---------------------------------------------");
        balanceOfEigenAgent = tokenL1.balanceOf(address(eigenAgent));
        balanceOfReceiverBefore = tokenL1.balanceOf(address(receiverContract));
        console.log("balanceOf(receiverContract):", balanceOfReceiverBefore);
        console.log("balanceOf(eigenAgent):", balanceOfEigenAgent);

        /////////////////////////////////////
        //// L1: Deposit with EigenAgent
        /////////////////////////////////////

        uint256 execNonce0 = 0; // no eigenAgent yet, execNonce is 0

        bytes memory messageWithSignature_D;
        {
            bytes memory depositMessage = encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_D = signMessageForEigenAgentExecution(
                bobKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager),
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
                messageWithSignature_D
            )) // CCIP abi.encodes a string message when sending
        });

        vm.selectFork(ethForkId);
        {
            vm.expectEmit(true, false, true, false); // don't check topic[2] EigenAgent address
            emit AgentFactory.AgentCreated(bob, vm.addr(1111), 1);
            receiverContract.mockCCIPReceive(any2EvmMessage);

            console.log("--------------- After Deposit -----------------");
            eigenAgent = agentFactory.getEigenAgent(bob);
            console.log("spawned eigenAgent: ", address(eigenAgent));

            require(
                tokenL1.balanceOf(address(receiverContract)) == (balanceOfReceiverBefore - amount),
                "receiverContract did not send tokens to EigenAgent after depositing"
            );
            console.log("balanceOf(receiverContract) after deposit:", tokenL1.balanceOf(address(receiverContract)));
            console.log("balanceOf(eigenAgent) after deposit:", tokenL1.balanceOf(address(eigenAgent)));
            uint256 eigenAgentShares = strategyManager.stakerStrategyShares(address(eigenAgent), strategy);
            console.log("eigenAgent shares after deposit:", eigenAgentShares);
            require(eigenAgentShares > 0, "eigenAgent should have >0 shares after deposit");
        }

        /////////////////////////////////////
        //// [L1] Queue Withdrawal with EigenAgent
        /////////////////////////////////////

        uint256 execNonce1 = eigenAgent.execNonce();

        bytes memory messageWithSignature_QW;
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
            messageWithSignature_QW = signMessageForEigenAgentExecution(
                bobKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager),
                withdrawalMessage,
                execNonce1,
                expiry
            );
        }

        vm.selectFork(ethForkId);
        {
            receiverContract.mockCCIPReceive(
                Client.Any2EVMMessage({
                    messageId: bytes32(uint256(9999)),
                    sourceChainSelector: BaseSepolia.ChainSelector, // Arb Sepolia source chain selector
                    sender: abi.encode(address(deployer)), // bytes: abi.decode(sender) if coming from an EVM chain.
                    destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging coins, just sending msg
                    data: abi.encode(string(
                        messageWithSignature_QW
                    ))
                })
            );

            console.log("--------------- After Queue Withdrawal -----------------");

            uint256 numWithdrawals = delegationManager.cumulativeWithdrawalsQueued(address(eigenAgent));
            require(numWithdrawals > 0, "must queueWithdrawals first before completeWithdrawals");

            console.log("balanceOf(receiver):", tokenL1.balanceOf(address(receiverContract)));
            console.log("balanceOf(eigenAgent):", tokenL1.balanceOf(address(eigenAgent)));

            uint256 eigenAgentSharesQW = strategyManager.stakerStrategyShares(address(eigenAgent), strategy);
            console.log("eigenAgent shares after queueWithdrawal:", eigenAgentSharesQW);
            require(eigenAgentSharesQW == 0, "eigenAgent should have 0 shares after queueWithdrawal");
        }
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_SenderL1_ReceiverL2_CompleteWithdrawal() public {

        uint256 amount = 0.003 ether;
        setupL1State_DepositAndQueueWithdrawal(amount);

        /////////////////////////////////////////////////////////////////
        //// [L1] Complete Queued Withdrawals
        /////////////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        uint256 execNonce2 = eigenAgent.execNonce();
        IDelegationManager.Withdrawal memory withdrawal;
        {
            uint32 startBlock = uint32(block.number);
            uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(bob);

            IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
            uint256[] memory sharesToWithdraw = new uint256[](1);
            strategiesToWithdraw[0] = strategy;
            sharesToWithdraw[0] = amount;

            withdrawal = IDelegationManager.Withdrawal({
                staker: address(eigenAgent),
                delegatedTo: delegationManager.delegatedTo(address(eigenAgent)),
                withdrawer: address(eigenAgent),
                nonce: withdrawalNonce,
                startBlock: startBlock,
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw
            });

        }
        bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);
        require(withdrawalRoot != 0, "withdrawal root missing, queueWithdrawal first");

        /////////////////////////////////////////////////////////////////
        //// 1. [L2] Send CompleteWithdrawals message to L2 Bridge
        /////////////////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        vm.assertEq(withdrawalRoot, senderHooks.calculateWithdrawalRoot(withdrawal));

        uint256 stakerBalanceOnL2Before = IERC20(BaseSepolia.BridgeToken).balanceOf(bob);

        bytes memory messageWithSignature_CW;
        {
            // create the completeWithdrawal message for Eigenlayer
            IERC20[] memory tokensToWithdraw = new IERC20[](1);
            tokensToWithdraw[0] = tokenL1;

            bytes memory completeWithdrawalMessage = encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                0, //middlewareTimesIndex,
                true // receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = signMessageForEigenAgentExecution(
                bobKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager),
                completeWithdrawalMessage,
                execNonce2,
                expiry
            );
        }

        bytes32 withdrawalTransferRoot = calculateWithdrawalTransferRoot(
            withdrawalRoot,
            amount,
            bob
        );
        vm.expectEmit(true, false, true, false);
        emit WithdrawalTransferRootCommitted(
            withdrawalTransferRoot,
            address(eigenAgent), // withdrawer
            amount,
            bob // signer
        );
        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_CW),
            address(BaseSepolia.BridgeToken), // destination token
            0, // not sending tokens, just message
            0 // use default gasLimit for this function
        );

        /////////////////////////////////////////////////////////////////
        //// [Offchain] CCIP relays tokens and message to L1 bridge
        /////////////////////////////////////////////////////////////////

        /////////////////////////////////////////////////////////////////
        //// 2. [L1] Mock receiving CompleteWithdrawals message on L1 Bridge
        /////////////////////////////////////////////////////////////////

        // fork ethsepolia so ReceiverCCIP -> Router calls work
        vm.selectFork(ethForkId);

        vm.warp(block.timestamp + 120); // 120 seconds = 10 blocks (12second per block)
        vm.roll((block.timestamp + 120) / 12);

        // sender contract is forked from testnet, addr will differ
        vm.expectEmit(false, true, true, false);
        emit ReceiverCCIP.BridgingWithdrawalToL2(
            address(senderContract),
            withdrawalTransferRoot,
            amount
        );
        // Mock L1 bridge receiving CCIP message and calling CompleteWithdrawal on Eigenlayer
        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(deployer),
                data: abi.encode(string(
                    messageWithSignature_CW
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );
        console.log("--------------- After Complete Withdrawal -----------------");

        // tokens in the ReceiverCCIP bridge contract
        console.log("balanceOf(receiverContract) after:", tokenL1.balanceOf(address(receiverContract)));
        console.log("balanceOf(eigenAgent) after:", tokenL1.balanceOf(address(eigenAgent)));
        console.log("balanceOf(restakingConnector) after:", tokenL1.balanceOf(address(restakingConnector)));
        console.log("balanceOf(router) after:", tokenL1.balanceOf(address(EthSepolia.Router)));
        require(
            tokenL1.balanceOf(address(receiverContract)) == (balanceOfReceiverBefore - amount),
            "receiverContract did not send tokens to L1 completeWithdrawal"
        );
        require(
            tokenL1.balanceOf(address(eigenAgent)) == 0,
            "EigenAgent did not send tokens to ReceiverCCIP after completeWithdrawal"
        );

        /////////////////////////////////////////////////////////////////
        //// [Offchain] CCIP relays tokens and message to L2 bridge
        /////////////////////////////////////////////////////////////////

        /////////////////////////////////////////////////////////////////
        //// 3. [L2] Mock receiving handleTransferToAgentOwner message from L1
        /////////////////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        // Mock SenderContract on L2 receiving the tokens and TransferToAgentOwner CCIP message from L1
        Client.EVMTokenAmount[] memory destTokenAmountsL2 = new Client.EVMTokenAmount[](1);
        destTokenAmountsL2[0] = Client.EVMTokenAmount({
            token: address(BaseSepolia.BridgeToken), // CCIP-BnM token address on L2
            amount: amount
        });
        senderContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(address(receiverContract)),
                data: abi.encode(string(
                    encodeHandleTransferToAgentOwnerMsg(
                        withdrawalTransferRoot
                    )
                )), // CCIP abi.encodes a string message when sending
                destTokenAmounts: destTokenAmountsL2
            })
        );

        uint256 stakerBalanceOnL2After = IERC20(BaseSepolia.BridgeToken).balanceOf(address(bob));
        console.log("--------------- L2 After Bridge back -----------------");
        console.log("balanceOf(bob) on L2 before:", stakerBalanceOnL2Before);
        console.log("balanceOf(bob) on L2 after:", stakerBalanceOnL2After);

        require(
            (stakerBalanceOnL2Before + amount) == stakerBalanceOnL2After,
            "balanceOf(bob) on L2 should increase by amount after L2 -> L2 withdrawal"
        );

        /////////////////////////////////////////////////////////////////
        //// Test Attempts to re-use WithdrawalAgentOwnerRoots
        /////////////////////////////////////////////////////////////////

        // attempting to commit a spent withdrawalTransferRoot should fail on L2
        vm.expectRevert("SenderHooks._commitWithdrawalTransferRootInfo: withdrawalTransferRoot already used");
        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_CW),
            address(BaseSepolia.BridgeToken), // destination token
            0, // not sending tokens, just message
            0 // use default gasLimit for this function
        );

        // attempting to re-use withdrawalTransferRoot from L1 should fail
        bytes memory messageWithdrawalReuse = encodeHandleTransferToAgentOwnerMsg(
            calculateWithdrawalTransferRoot(
                withdrawalRoot,
                amount,
                bob
            )
        );
        vm.expectRevert("SenderHooks.handleTransferToAgentOwner: withdrawalTransferRoot already used");
        senderContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(address(receiverContract)),
                data: abi.encode(string(
                    messageWithdrawalReuse
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );

        ISenderHooks.WithdrawalTransfer memory wt = senderHooks.getWithdrawalTransferCommitment(
            withdrawalTransferRoot
        );
        vm.assertEq(wt.amount, amount);
        vm.assertEq(wt.agentOwner, bob);

        // withdrawalTransferRoot should be spent now
        vm.assertEq(senderHooks.isWithdrawalTransferRootSpent(withdrawalTransferRoot), true);
    }

}
