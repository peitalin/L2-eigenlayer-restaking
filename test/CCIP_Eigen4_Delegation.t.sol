// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {IERC20Minter} from "../src/interfaces/IERC20Minter.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {IReceiverCCIPMock} from "./mocks/ReceiverCCIPMock.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderCCIPMock} from "./mocks/SenderCCIPMock.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {ClientSigners} from "../script/ClientSigners.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";


contract CCIP_Eigen_DelegationTests is Test {

    DeployReceiverOnL1Script public deployReceiverOnL1Script;
    DeploySenderOnL2Script public deployOnL2Script;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    ClientSigners public clientSigners;

    IReceiverCCIPMock public receiverContract;
    ISenderCCIPMock public senderContract;
    IRestakingConnector public restakingConnector;
    IAgentFactory public agentFactory;

    IStrategyManager public strategyManager;
    IPauserRegistry public _pauserRegistry;
    IRewardsCoordinator public _rewardsCoordinator;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    IERC20 public tokenL1;

    uint256 deployerKey;
    address deployer;
    IEigenAgent6551 eigenAgent;

    uint256 operatorKey;
    address operator;
    uint256 operator2Key;
    address operator2;

    uint256 amount = 0.0091 ether;
    uint256 l2ForkId;
    uint256 ethForkId;

    function setUp() public {

        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
        deployOnL2Script = new DeploySenderOnL2Script();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        clientSigners = new ClientSigners();

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        operatorKey = uint256(88888);
        operator = vm.addr(operatorKey);

        operator2Key = uint256(99999);
        operator2 = vm.addr(operator2Key);

        l2ForkId = vm.createFork("basesepolia");        // 0
        ethForkId = vm.createSelectFork("ethsepolia"); // 1

        (
            strategy,
            strategyManager,
            , //IStrategyFactory
            _pauserRegistry,
            delegationManager,
            _rewardsCoordinator,
            tokenL1
        ) = deployMockEigenlayerContractsScript.deployEigenlayerContracts(false);

        //////////// Arb Sepolia ////////////
        vm.selectFork(l2ForkId);
        senderContract = deployOnL2Script.mockrun();


        //////////// Eth Sepolia ////////////
        vm.selectFork(ethForkId);
        (
            receiverContract,
            restakingConnector,
            agentFactory
        ) = deployReceiverOnL1Script.mockrun();


        //////////// Arb Sepolia ////////////
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);
        // allow L2 sender contract to receive tokens back from L1
        senderContract.allowlistSourceChain(EthSepolia.ChainSelector, true);
        senderContract.allowlistSender(address(receiverContract), true);
        senderContract.allowlistSender(deployer, true);
        // fund L2 sender with gas and CCIP-BnM tokens
        vm.deal(address(senderContract), 1 ether); // fund for gas
        if (block.chainid == BaseSepolia.ChainId) {
            // drip() using CCIP's BnM faucet if forking from Arb Sepolia
            IERC20_CCIPBnM(BaseSepolia.BridgeToken).drip(address(senderContract));
        } else {
            // mint() if we deployed our own Mock ERC20
            IERC20Minter(BaseSepolia.BridgeToken).mint(address(senderContract), 1 ether);
        }
        vm.stopBroadcast();


        //////////// Eth Sepolia ////////////
        vm.selectFork(ethForkId);

        vm.startBroadcast(deployerKey);
        receiverContract.allowlistSender(deployer, true);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

        // fund L1 receiver with gas and CCIP-BnM tokens
        vm.deal(address(receiverContract), 1 ether); // fund for gas
        if (block.chainid == EthSepolia.ChainId) {
            // drip() using CCIP's BnM faucet if forking from Eth Sepolia
            IERC20_CCIPBnM(address(tokenL1)).drip(address(receiverContract));
        } else {
            // mint() if we deployed our own Mock ERC20
            IERC20Minter(address(tokenL1)).mint(address(receiverContract), 1 ether);
        }

        vm.stopBroadcast();

        /////////////////////////////////////
        //// Register Operators
        /////////////////////////////////////

        /// Operator 1
        vm.startBroadcast(operatorKey);
        IDelegationManager.OperatorDetails memory registeringOperatorDetails =
            IDelegationManager.OperatorDetails({
                __deprecated_earningsReceiver: vm.addr(0xb0b),
                delegationApprover: operator,
                stakerOptOutWindowBlocks: 4
            });

        delegationManager.registerAsOperator(registeringOperatorDetails, "operator 1 metadata");

        require(delegationManager.isOperator(operator), "operator not set");

        vm.stopBroadcast();

        /// Operator 2
        vm.startBroadcast(operator2Key);
        IDelegationManager.OperatorDetails memory registeringOperatorDetails2 =
            IDelegationManager.OperatorDetails({
                __deprecated_earningsReceiver: vm.addr(0xb0b),
                delegationApprover: operator2,
                stakerOptOutWindowBlocks: 4
            });

        delegationManager.registerAsOperator(registeringOperatorDetails2, "operator 2 metadata");

        require(delegationManager.isOperator(operator2), "operator2 not set");
        vm.stopBroadcast();

        /////////////////////////////////////
        //// Deposit with EigenAgent
        /////////////////////////////////////

        vm.startBroadcast(deployerKey);

        uint256 expiry = block.timestamp + 1 days;
        uint256 execNonce0 = 0; // no eigenAgent yet, execNonce is 0

        bytes memory depositMessage;
        bytes memory messageWithSignature_D;
        {
            depositMessage = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_D = clientSigners.signMessageForEigenAgentExecution(
                deployerKey,
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


    function createDelegateMessage(uint256 _operatorKey, uint256 _execNonce)
        public view
        returns (bytes memory messageWithSignature_DT)
    {
        // Operator Approver signs the delegateTo call
        bytes32 approverSalt = bytes32(uint256(222222));
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;
        address _operator = vm.addr(_operatorKey);
        {
            uint256 sig1_expiry = block.timestamp + 1 hours;
            bytes32 digestHash1 = clientSigners.calculateDelegationApprovalDigestHash(
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
            approverSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature1,
                expiry: sig1_expiry
            });
        }
            // append user signature for EigenAgent execution
        {
            uint256 expiry2 = block.timestamp + 1 hours;

            bytes memory delegateToMessage = EigenlayerMsgEncoders.encodeDelegateTo(
                _operator,
                approverSignatureAndExpiry,
                approverSalt
            );
            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_DT = clientSigners.signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(delegationManager), // DelegationManager.delegateTo()
                delegateToMessage,
                _execNonce,
                expiry2
            );
        }
        return messageWithSignature_DT;
    }


    function test_Eigenlayer_DelegateTo() public {

        uint256 execNonce1 = eigenAgent.execNonce();
        bytes memory messageWithSignature_DT = createDelegateMessage(operatorKey, execNonce1);

        vm.expectEmit(true, true, false, false);
        emit IDelegationManager.StakerDelegated(address(eigenAgent), operator);

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
        require(
            delegationManager.operatorShares(operator, strategy) == amount,
            "operator should have shares delegated to it"
        );
    }


    function test_Eigenlayer_Undelegate_Delegate_Redeposit() public {

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
        require(
            delegationManager.operatorShares(operator, strategy) == amount,
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
            bytes memory message_UD = EigenlayerMsgEncoders.encodeUndelegateMsg(
                address(eigenAgent)
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_UD = clientSigners.signMessageForEigenAgentExecution(
                deployerKey,
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

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: address(eigenAgent),
            delegatedTo: address(operator), // previous operator that eigenAgent was delegated to
            withdrawer: address(eigenAgent),
            nonce: withdrawalNonce,
            startBlock: startBlock,
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
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
        require(withdrawal.shares[0] == amount, "shares should equal amount");

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
            completeWithdrawalMessage = EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                0, //middlewareTimesIndex,
                receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = clientSigners.signMessageForEigenAgentExecution(
                deployerKey,
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
            delegationManager.operatorShares(operator2, strategy) == amount,
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
        require(
            delegationManager.operatorShares(operator, strategy) == amount,
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
            bytes memory message_UD = EigenlayerMsgEncoders.encodeUndelegateMsg(
                address(eigenAgent)
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_UD = clientSigners.signMessageForEigenAgentExecution(
                deployerKey,
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

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: address(eigenAgent),
            delegatedTo: address(operator), // previous operator that eigenAgent was delegated to
            withdrawer: address(eigenAgent),
            nonce: withdrawalNonce,
            startBlock: startBlock,
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
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
        require(withdrawal.shares[0] == amount, "shares should equal amount");

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
            completeWithdrawalMessage = EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                0, //middlewareTimesIndex,
                receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = clientSigners.signMessageForEigenAgentExecution(
                deployerKey,
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
        require(
            delegationManager.operatorShares(operator2, strategy) == 0,
            "operator2 should have NO shares delegated to it"
        );

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
        require(
            delegationManager.operatorShares(operator2, strategy) == amount,
            "operator2 should have shares delegated to it"
        );
    }

}
