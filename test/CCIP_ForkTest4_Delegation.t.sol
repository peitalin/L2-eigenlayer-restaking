// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin-v47-contracts/token/ERC20/IERC20.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerEvents} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer-contracts/interfaces/ISignatureUtilsMixin.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";


contract CCIP_ForkTest_Delegation_Tests is BaseTestEnvironment {

    uint256 operatorKey;
    address operator;

    uint256 operator2Key;
    address operator2;

    uint256 amount = 0.0091 ether;
    uint32 allocationDelay = 100;

    function setUp() public {

        setUpForkedEnvironment();

        /////////////////////////////////////
        //// Register Operators
        /////////////////////////////////////
        vm.selectFork(ethForkId);

        operatorKey = uint256(88888);
        operator = vm.addr(operatorKey);

        operator2Key = uint256(99999);
        operator2 = vm.addr(operator2Key);

        /// Operator 1
        vm.startBroadcast(operatorKey);
        {
            delegationManager.registerAsOperator(operator, allocationDelay, "operator 1 metadata");
            require(delegationManager.isOperator(operator), "operator not set");
        }
        vm.stopBroadcast();

        /// Operator 2
        vm.startBroadcast(operator2Key);
        {
            delegationManager.registerAsOperator(
                operator2,
                allocationDelay,
                "operator 2 metadata"
            );

            require(delegationManager.isOperator(operator2), "operator2 not set");
        }
        vm.stopBroadcast();

        /////////////////////////////////////
        //// Deposit with EigenAgent
        /////////////////////////////////////

        vm.startBroadcast(deployerKey);

        uint256 expiry = block.timestamp + 1 days;
        uint256 execNonce0 = 0; // no eigenAgent yet, execNonce is 0

        eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);

        bytes memory depositMessage;
        bytes memory messageWithSignature_D;
        {
            depositMessage = encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_D = signMessageForEigenAgentExecution(
                deployerKey,
                address(eigenAgent),
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

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: destTokenAmounts,
                data: abi.encode(string(
                    messageWithSignature_D
                )) // CCIP abi.encodes a string message when sending
            })
        );

        eigenAgent = agentFactory.getEigenAgent(deployer);

        vm.stopBroadcast();
    }

    /*
     *
     *
     *             Functions
     *
     *
     */

    function createDelegateMessage(uint256 _operatorKey, uint256 _execNonce)
        public view
        returns (bytes memory messageWithSignature_DT)
    {
        // Operator Approver signs the delegateTo call
        bytes32 approverSalt = bytes32(uint256(222222));
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory approverSignatureAndExpiry;
        address _operator = vm.addr(_operatorKey);
        {
            uint256 sig1_expiry = block.timestamp + 1 hours;
            bytes32 digestHash1 = calculateDelegationApprovalDigestHash(
                address(eigenAgent), // staker == msg.sender == eigenAgent from Eigenlayer's perspective
                _operator, // operator
                _operator, // _delegationApprover,
                approverSalt,
                sig1_expiry,
                address(delegationManager), // delegationManagerAddr
                block.chainid
            );
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(_operatorKey, digestHash1);
            bytes memory signature1 = abi.encodePacked(r, s, v);
            approverSignatureAndExpiry = ISignatureUtilsMixinTypes.SignatureWithExpiry({
                signature: signature1,
                expiry: sig1_expiry
            });
        }
            // append user signature for EigenAgent execution
        {
            uint256 expiry2 = block.timestamp + 1 hours;

            bytes memory delegateToMessage = encodeDelegateTo(
                _operator,
                approverSignatureAndExpiry,
                approverSalt
            );
            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_DT = signMessageForEigenAgentExecution(
                deployerKey,
                address(eigenAgent),
                block.chainid, // destination chainid where EigenAgent lives
                address(delegationManager), // DelegationManager.delegateTo()
                delegateToMessage,
                _execNonce,
                expiry2
            );
        }
        return messageWithSignature_DT;
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_Eigenlayer_DelegateTo() public {

        uint256 execNonce1 = eigenAgent.execNonce();
        bytes memory messageWithSignature_DT = createDelegateMessage(operatorKey, execNonce1);

        vm.expectEmit(true, true, false, false);
        emit IDelegationManagerEvents.StakerDelegated(address(eigenAgent), operator);

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging any tokens
                data: abi.encode(string(
                    messageWithSignature_DT
                ))
            })
        );

        require(
            delegationManager.delegatedTo(address(eigenAgent)) == address(operator),
            "eigenAgent should be delegated to operator"
        );

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy;
        uint256[] memory op1Shares = delegationManager.getOperatorShares(operator, strategies);
        require(
            op1Shares.length > 0 && op1Shares[0] == amount,
            "operator should have shares delegated to it"
        );
    }


    function test_FullFlow_Undelegate_Delegate_Redeposit() public {

        // This test follows the order:
        // (1) delegate
        // (2) undelegate
        // (3) re-delegating to a new operator, then
        // (4) re-depositing via completeWithdrawals(receiveAsTokens: false)

        ///////////////////////////////////////
        ///// Delegate to Operator 1
        ///////////////////////////////////////

        uint256 execNonce1 = 1;
        bytes memory messageWithSignature_DT = createDelegateMessage(operatorKey, execNonce1);

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging any tokens
                data: abi.encode(string(
                    messageWithSignature_DT
                ))
            })
        );

        require(
            delegationManager.delegatedTo(address(eigenAgent)) == address(operator),
            "eigenAgent should be delegated to operator"
        );

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy;
        uint256[] memory op1Shares = delegationManager.getOperatorShares(operator, strategies);
        require(
            op1Shares.length > 0 && op1Shares[0] == amount,
            "operator should have shares delegated to it"
        );

        ///////////////////////////////////////
        ///// (1) Undelegate from Operator 1
        ///////////////////////////////////////

        uint256 execNonce2 = eigenAgent.execNonce();
        uint32 startBlock = uint32(block.number); // save startBlock before undelegating

        bytes memory messageWithSignature_UD;
        {
            uint256 expiry = block.timestamp + 1 hours;
            bytes memory message_UD = encodeUndelegateMsg(
                address(eigenAgent)
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_UD = signMessageForEigenAgentExecution(
                deployerKey,
                address(eigenAgent),
                block.chainid, // destination chainid where EigenAgent lives
                address(delegationManager), // DelegationManager
                message_UD,
                execNonce2,
                expiry
            );
        }

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging any tokens
                data: abi.encode(string(
                    messageWithSignature_UD
                ))
            })
        );

        require(
            delegationManager.delegatedTo(address(eigenAgent)) == address(0),
            "eigenAgent should no longer be delegated to any operator"
        );

        uint256 execNonce3 = eigenAgent.execNonce();
        bytes memory messageWithSignature_DT2 = createDelegateMessage(operator2Key, execNonce3);

        //////////////////////////////////////////
        /// (2) Delegate to other Operator 2
        //////////////////////////////////////////
        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging any tokens
                data: abi.encode(string(
                    messageWithSignature_DT2
                ))
            })
        );

        require(
            delegationManager.delegatedTo(address(eigenAgent)) == address(operator2),
            "eigenAgent should be delegated to operator2"
        );

        //////////////////////////////////////////
        /// (3) Redeposit Shares back (delegated to Operator 2)
        //////////////////////////////////////////

        uint256 execNonce4 = eigenAgent.execNonce();
        uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(address(eigenAgent)) - 1;

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);
        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = amount;

        IDelegationManagerTypes.Withdrawal memory withdrawal = IDelegationManagerTypes.Withdrawal({
            staker: address(eigenAgent),
            delegatedTo: address(operator), // previous operator that eigenAgent was delegated to
            withdrawer: address(eigenAgent),
            nonce: withdrawalNonce,
            startBlock: startBlock,
            strategies: strategiesToWithdraw,
            scaledShares: sharesToWithdraw
        });

        // require the following to match, so that the withdrawalRoot calculated inside Eigenlayer
        // matches when we re-deposit into Eigenlayer strategy vaults via
        // `completeWithdrawals(receiveAsTokens = false)`.
        require(withdrawal.staker == address(eigenAgent), "staker should be eigenAgent");
        require(withdrawal.withdrawer == address(eigenAgent), "withdrawer should be eigenAgent");
        require(withdrawal.delegatedTo == operator, "should be previous operator (when undelegating)");
        require(withdrawal.nonce == 0, "should be nonce at the time of undelegating");
        require(withdrawal.startBlock == startBlock, "startBlock issue");
        require(address(withdrawal.strategies[0]) == address(strategy), "strategy does not match");
        require(withdrawal.scaledShares[0] == amount, "shares should equal amount");

        bytes memory completeWithdrawalMessage;
        bytes memory messageWithSignature_CW;
        {
            uint256 expiry = block.timestamp + 1 hours;
            // create the completeWithdrawal message for Eigenlayer
            IERC20[] memory tokensToWithdraw = new IERC20[](1);
            tokensToWithdraw[0] = tokenL1;

            bool receiveAsTokens = false;
            // receiveAsTokens == false to redeposit as shares back into Eigenlayer
            // if receiveAsTokens == true, tokens are withdrawn back to EigenAgent
            completeWithdrawalMessage = encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = signMessageForEigenAgentExecution(
                deployerKey,
                address(eigenAgent),
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager),
                completeWithdrawalMessage,
                execNonce4,
                expiry
            );
        }

        // wait at least stakerOptOutWindowBlocks == 4 blocks to re-deposit.
        vm.warp(block.timestamp + 120); // 120 seconds = 10 blocks (12second per block)
        vm.roll((block.timestamp + 120) / 12);

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

        IStrategy[] memory strategies_A = new IStrategy[](1);
        strategies_A[0] = strategy;
        uint256[] memory op2Shares_A = delegationManager.getOperatorShares(operator2, strategies_A);

        require(
            op2Shares_A.length > 0,
            "operator2 should have shares"
        );
        require(
            op2Shares_A[0] == amount,
            "operator2 should have shares delegated to it"
        );
    }

    function test_Eigenlayer_Undelegate_Redeposit_Delegate() public {

        // This test swaps the order:
        // (1) delegate
        // (2) undelegate
        // (4) re-depositing via completeWithdrawals(receiveAsTokens: false), then
        // (3) re-delegating to a new operator

        ///////////////////////////////////////
        ///// Delegate to Operator 1
        ///////////////////////////////////////

        uint256 execNonce1 = 1;
        bytes memory messageWithSignature_DT = createDelegateMessage(operatorKey, execNonce1);

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging any tokens
                data: abi.encode(string(
                    messageWithSignature_DT
                ))
            })
        );

        require(
            delegationManager.delegatedTo(address(eigenAgent)) == address(operator),
            "eigenAgent should be delegated to operator"
        );

        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy;
        uint256[] memory op1Shares = delegationManager.getOperatorShares(operator, strategies);
        require(
            op1Shares.length > 0 && op1Shares[0] == amount,
            "operator should have shares delegated to it"
        );

        ///////////////////////////////////////
        ///// (1) Undelegate from Operator 1
        ///////////////////////////////////////

        uint256 execNonce2 = eigenAgent.execNonce();
        uint32 startBlock = uint32(block.number); // save startBlock before undelegating

        bytes memory messageWithSignature_UD;
        {
            uint256 expiry = block.timestamp + 1 hours;
            bytes memory message_UD = encodeUndelegateMsg(
                address(eigenAgent)
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_UD = signMessageForEigenAgentExecution(
                deployerKey,
                address(eigenAgent),
                block.chainid, // destination chainid where EigenAgent lives
                address(delegationManager), // DelegationManager
                message_UD,
                execNonce2,
                expiry
            );
        }

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging any tokens
                data: abi.encode(string(
                    messageWithSignature_UD
                ))
            })
        );

        require(
            delegationManager.delegatedTo(address(eigenAgent)) == address(0),
            "eigenAgent should no longer be delegated to any operator"
        );

        //////////////////////////////////////////
        /// (3) Redeposit Shares back (delegated to Operator 2)
        //////////////////////////////////////////

        uint256 execNonce4 = eigenAgent.execNonce();
        uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(address(eigenAgent)) - 1;

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);
        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = amount;

        IDelegationManagerTypes.Withdrawal memory withdrawal = IDelegationManagerTypes.Withdrawal({
            staker: address(eigenAgent),
            delegatedTo: address(operator), // previous operator that eigenAgent was delegated to
            withdrawer: address(eigenAgent),
            nonce: withdrawalNonce,
            startBlock: startBlock,
            strategies: strategiesToWithdraw,
            scaledShares: sharesToWithdraw
        });

        // require the following to match, so that the withdrawalRoot calculated inside Eigenlayer
        // matches when we re-deposit into Eigenlayer strategy vaults via
        // `completeWithdrawals(receiveAsTokens = false)`.
        require(withdrawal.staker == address(eigenAgent), "staker should be eigenAgent");
        require(withdrawal.withdrawer == address(eigenAgent), "withdrawer should be eigenAgent");
        require(withdrawal.delegatedTo == operator, "should be previous operator (when undelegating)");
        require(withdrawal.nonce == 0, "should be nonce at the time of undelegating");
        require(withdrawal.startBlock == startBlock, "startBlock issue");
        require(address(withdrawal.strategies[0]) == address(strategy), "strategy does not match");
        require(withdrawal.scaledShares[0] == amount, "shares should equal amount");

        bytes memory completeWithdrawalMessage;
        bytes memory messageWithSignature_CW;
        {
            uint256 expiry = block.timestamp + 1 hours;
            // create the completeWithdrawal message for Eigenlayer
            IERC20[] memory tokensToWithdraw = new IERC20[](1);
            tokensToWithdraw[0] = tokenL1;

            bool receiveAsTokens = false;
            // receiveAsTokens == false to redeposit as shares back into Eigenlayer
            // if receiveAsTokens == true, tokens are withdrawn back to EigenAgent
            completeWithdrawalMessage = encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = signMessageForEigenAgentExecution(
                deployerKey,
                address(eigenAgent),
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager),
                completeWithdrawalMessage,
                execNonce4,
                expiry
            );
        }

        // wait at least stakerOptOutWindowBlocks == 4 blocks to re-deposit.
        vm.warp(block.timestamp + 120); // 120 seconds = 10 blocks (12second per block)
        vm.roll((block.timestamp + 120) / 12);

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

        require(
            delegationManager.delegatedTo(address(eigenAgent)) == address(0),
            "eigenAgent should not be delegated to anyone"
        );

        IStrategy[] memory strategies_B = new IStrategy[](1);
        strategies_B[0] = strategy;

        uint256[] memory op2Shares_B = delegationManager.getOperatorShares(operator2, strategies_B);
        if (op2Shares_B.length > 0) {
            require(
                op2Shares_B[0] == 0,
                "operator2 should have NO shares delegated to it"
            );
        }

        //////////////////////////////////////////
        /// (2) Delegate to other Operator 2
        //////////////////////////////////////////
        uint256 execNonce3 = eigenAgent.execNonce();
        bytes memory messageWithSignature_DT2 = createDelegateMessage(operator2Key, execNonce3);

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging any tokens
                data: abi.encode(string(
                    messageWithSignature_DT2
                ))
            })
        );

        require(
            delegationManager.delegatedTo(address(eigenAgent)) == address(operator2),
            "eigenAgent should be delegated to operator2"
        );

        IStrategy[] memory strategies_C = new IStrategy[](1);
        strategies_C[0] = strategy;

        uint256[] memory op2Shares_C = delegationManager.getOperatorShares(operator2, strategies_C);
        require(
            op2Shares_C.length > 0 && op2Shares_C[0] == amount,
            "operator2 should have shares delegated to it"
        );
    }

}
