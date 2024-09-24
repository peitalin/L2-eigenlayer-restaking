// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {ISignatureUtils} from "@eigenlayer-contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    AgentOwnerSignature,
    EigenlayerMsgDecoders,
    CompleteWithdrawalsArrayDecoder,
    DelegationDecoders,
    TransferToAgentOwnerMsg
} from "../src/utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {FunctionSelectorDecoder} from "../src/utils/FunctionSelectorDecoder.sol";
import {EthSepolia} from "../script/Addresses.sol";


contract UnitTests_MsgEncodingDecoding is BaseTestEnvironment {

    EigenlayerMsgDecoders public eigenlayerMsgDecoders;

    uint256 amount;
    address staker;
    uint256 expiry;
    uint256 execNonce;

    function setUp() public {

        setUpLocalEnvironment();

        eigenlayerMsgDecoders = new EigenlayerMsgDecoders();

        amount = 0.0077 ether;
        staker = deployer;
        expiry = 86421;
        execNonce = 0;
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_DecodeFunctionSelectors() public view {

        bytes memory message1 = hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000044f7e784ef00000000000000000000000000000000000000000000000000000000000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c00000000000000000000000000000000000000000000000000000000";
        bytes4 functionSelector1 = FunctionSelectorDecoder.decodeFunctionSelector(message1);
        require(functionSelector1 == 0xf7e784ef, "functionSelector invalid");

        bytes memory message2 = abi.encode(string(abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")),
            expiry,
            address(strategy),
            address(tokenL1),
            amount,
            staker,
            hex"3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c"
        )));
        bytes4 functionSelector2 = FunctionSelectorDecoder.decodeFunctionSelector(message2);
        require(functionSelector2 == 0x32e89ace, "functionSelector2 invalid");
    }

    function test_Decode_AgentOwnerSignature() public view {

        bytes memory messageToEigenlayer = encodeDepositIntoStrategyMsg(
            address(strategy),
            address(tokenL1),
            amount
        );

        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            deployerKey,
            block.chainid,
            address(strategy),
            messageToEigenlayer,
            execNonce,
            expiry
        );

        (
            // message
            address _strategy,
            address _token,
            uint256 _amount,
            // message signature
            address _signer,
            uint256 _expiry,
            bytes memory _signature
        ) = eigenlayerMsgDecoders.decodeDepositIntoStrategyMsg(
            // CCIP string and encodes message when sending
            abi.encode(string(messageWithSignature))
        );

        (
            address _signer2,
            uint256 _expiry2,
            bytes memory _signature2
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(
            abi.encode(string(messageWithSignature)),
            196
        ); // for depositIntoStrategy

        // compare vs original inputs
        vm.assertEq(_signer, vm.addr(deployerKey));
        vm.assertEq(_expiry, expiry);
        vm.assertEq(_amount, amount);
        vm.assertEq(_token, address(tokenL1));
        vm.assertEq(_strategy, address(strategy));

        // compare decodeAgentOwner vs decodeDepositIntoStrategy
        vm.assertEq(_signer, _signer2);
        vm.assertEq(_expiry, _expiry2);
        vm.assertEq(keccak256(_signature), keccak256(_signature2));
    }

    function test_Decode_MintEigenAgent() public view {

        // use EigenlayerMsgEncoders for coverage.
        bytes memory messageToMint = EigenlayerMsgEncoders.encodeMintEigenAgentMsg(staker);
        // CCIP turns the message into string when sending
        bytes memory messageCCIP = abi.encode(string(messageToMint));

        address recipient = eigenlayerMsgDecoders.decodeMintEigenAgent(messageCCIP);

        vm.assertEq(recipient, staker);
    }

    /*
     *
     *
     *                   Deposits
     *
     *
    */

    function test_Decode_DepositIntoStrategy6551Msg() public view {

        bytes memory messageToEigenlayer = encodeDepositIntoStrategyMsg(
            address(strategy),
            address(tokenL1),
            amount
        );

        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            deployerKey,
            block.chainid,
            address(strategy),
            messageToEigenlayer,
            execNonce,
            expiry
        );

        // CCIP turns the message into string when sending
        bytes memory messageWithSignatureCCIP = abi.encode(string(messageWithSignature));

        (
            // message
            address _strategy,
            address _token,
            uint256 _amount,
            // message signature
            address _signer,
            uint256 _expiry,
            bytes memory _signature
        ) = eigenlayerMsgDecoders.decodeDepositIntoStrategyMsg(messageWithSignatureCCIP);

        vm.assertEq(address(_strategy), address(strategy));
        vm.assertEq(address(tokenL1), _token);
        vm.assertEq(amount, _amount);

        vm.assertEq(_signature.length, 65);
        vm.assertEq(_signer, staker);
        vm.assertEq(expiry, _expiry);
    }

    /*
     *
     *
     *                   Queue Withdrawals
     *
     *
    */

    function test_Decode_Array_QueueWithdrawals() public view {

        IStrategy[] memory strategiesToWithdraw0 = new IStrategy[](1);
        strategiesToWithdraw0[0] = IStrategy(0xb111111AD20E9d85d5152aE68f45f40A11111111);
        IStrategy[] memory strategiesToWithdraw1 = new IStrategy[](2);
        strategiesToWithdraw1[0] = IStrategy(0xb222222AD20e9D85d5152ae68F45f40a22222222);
        strategiesToWithdraw1[1] = IStrategy(0xc666666bb11e9D85D5152AE68f45f40a66666666);
        IStrategy[] memory strategiesToWithdraw2 = new IStrategy[](3);
        strategiesToWithdraw2[0] = IStrategy(0xb333333AD20e9D85D5152aE68f45F40A33333333);
        strategiesToWithdraw2[1] = IStrategy(0xC444444Ad20E9d85d5152ae68F45F40a44444444);
        strategiesToWithdraw2[2] = IStrategy(0xd555555AD20E9d85D5152aE68F45F40a55555555);

        uint256[] memory sharesToWithdraw0 = new uint256[](1);
        sharesToWithdraw0[0] = 0.010101 ether;
        uint256[] memory sharesToWithdraw1 = new uint256[](2);
        sharesToWithdraw1[0] = 0.020202 ether;
        sharesToWithdraw1[1] = 0.060606 ether;
        uint256[] memory sharesToWithdraw2 = new uint256[](3);
        sharesToWithdraw2[0] = 0.030303 ether;
        sharesToWithdraw2[1] = 0.040404 ether;
        sharesToWithdraw2[2] = 0.050505 ether;

        IDelegationManager.QueuedWithdrawalParams[] memory QWPArray =
            new IDelegationManager.QueuedWithdrawalParams[](3);

        {
            IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal0;
            IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal1;
            IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal2;

            queuedWithdrawal0 = IDelegationManager.QueuedWithdrawalParams({
                strategies: strategiesToWithdraw0,
                shares: sharesToWithdraw0,
                withdrawer: deployer
            });
            queuedWithdrawal1 = IDelegationManager.QueuedWithdrawalParams({
                strategies: strategiesToWithdraw1,
                shares: sharesToWithdraw1,
                withdrawer: vm.addr(0x1)
            });
            queuedWithdrawal2 = IDelegationManager.QueuedWithdrawalParams({
                strategies: strategiesToWithdraw2,
                shares: sharesToWithdraw2,
                withdrawer: vm.addr(0x2)
            });

            QWPArray[0] = queuedWithdrawal0;
            QWPArray[1] = queuedWithdrawal1;
            QWPArray[2] = queuedWithdrawal2;
        }

        bytes memory message_QW;
        bytes memory messageWithSignature_QW;
        {
            message_QW = encodeQueueWithdrawalsMsg(
                QWPArray
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_QW = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                message_QW,
                execNonce,
                expiry
            );
        }

        (
            IDelegationManager.QueuedWithdrawalParams[] memory decodedQW,
            address signer,
            uint256 expiry2,
            bytes memory _signature
        ) = eigenlayerMsgDecoders.decodeQueueWithdrawalsMsg(
            // CCIP string-encodes the message when sending
            abi.encode(string(
                messageWithSignature_QW
            ))
        );

        // signature
        vm.assertEq(_signature.length, 65);
        vm.assertEq(signer, deployer);
        vm.assertEq(expiry, expiry2);
        // strategies
        vm.assertEq(address(decodedQW[0].strategies[0]), address(strategiesToWithdraw0[0]));
        vm.assertEq(address(decodedQW[1].strategies[0]), address(strategiesToWithdraw1[0]));
        vm.assertEq(address(decodedQW[1].strategies[1]), address(strategiesToWithdraw1[1]));
        vm.assertEq(address(decodedQW[2].strategies[0]), address(strategiesToWithdraw2[0]));
        vm.assertEq(address(decodedQW[2].strategies[1]), address(strategiesToWithdraw2[1]));
        vm.assertEq(address(decodedQW[2].strategies[2]), address(strategiesToWithdraw2[2]));
        // shares
        vm.assertEq(decodedQW[0].shares[0], sharesToWithdraw0[0]);
        vm.assertEq(decodedQW[1].shares[0], sharesToWithdraw1[0]);
        vm.assertEq(decodedQW[1].shares[1], sharesToWithdraw1[1]);
        vm.assertEq(decodedQW[2].shares[0], sharesToWithdraw2[0]);
        vm.assertEq(decodedQW[2].shares[1], sharesToWithdraw2[1]);
        vm.assertEq(decodedQW[2].shares[2], sharesToWithdraw2[2]);
        // withdrawers
        vm.assertEq(decodedQW[0].withdrawer, QWPArray[0].withdrawer);
        vm.assertEq(decodedQW[1].withdrawer, QWPArray[1].withdrawer);
        vm.assertEq(decodedQW[2].withdrawer, QWPArray[2].withdrawer);
    }

    function test_Decode_Revert_ZeroLenArray_QueueWithdrawals() public {

        IDelegationManager.QueuedWithdrawalParams[] memory QWPArray =
            new IDelegationManager.QueuedWithdrawalParams[](0);

        bytes memory message_QW;
        bytes memory messageWithSignature_QW;
        {
            message_QW = encodeQueueWithdrawalsMsg(
                QWPArray
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_QW = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                message_QW,
                execNonce,
                expiry
            );
        }

        vm.expectRevert("decodeQueueWithdrawalsMsg: arrayLength must be at least 1");
        eigenlayerMsgDecoders.decodeQueueWithdrawalsMsg(
            // CCIP string-encodes the message when sending
            abi.encode(string(
                messageWithSignature_QW
            ))
        );
    }

    /*
     *
     *
     *                   Complete Withdrawals
     *
     *
    */

    function test_Decode_CompleteQueuedWithdrawal_Single() public view {

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);

        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = 0.00321 ether;

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: deployer,
            delegatedTo: address(0x0),
            withdrawer: deployer,
            nonce: 0,
            startBlock: uint32(block.number),
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
        });

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = tokenL1;
        uint256 middlewareTimesIndex = 0; // not used, used when slashing is enabled;
        bool receiveAsTokens = true;

        bytes memory message_CW;
        bytes memory messageWithSignature_CW;
        {
            message_CW = encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                middlewareTimesIndex,
                receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                message_CW,
                execNonce,
                expiry
            );
        }

        (
            IDelegationManager.Withdrawal memory _withdrawal,
            IERC20[] memory _tokensToWithdraw,
            , // uint256 _middlewareTimesIndex
            bool _receiveAsTokens,
            address _signer,
            uint256 _expiry,
            bytes memory _signature
        ) = eigenlayerMsgDecoders.decodeCompleteWithdrawalMsg(
            // CCIP string-encodes the message when sending
            abi.encode(string(
                messageWithSignature_CW
            ))
        );

        vm.assertEq(_signature.length, 65);
        vm.assertEq(_signer, deployer);
        vm.assertEq(_expiry, expiry);

        vm.assertEq(_withdrawal.shares[0], withdrawal.shares[0]);
        vm.assertEq(_withdrawal.staker, withdrawal.staker);
        vm.assertEq(_withdrawal.withdrawer, withdrawal.withdrawer);
        vm.assertEq(address(_tokensToWithdraw[0]), address(tokensToWithdraw[0]));
        vm.assertEq(_receiveAsTokens, receiveAsTokens);
    }

    function test_FunctionSelectors_CompleteQueueWithdrawal() public pure {
        bytes4 fselector1 = IDelegationManager.completeQueuedWithdrawal.selector;
        bytes4 fselector2 = bytes4(keccak256("completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],uint256,bool)"));
        // bytes4 fselector3 = 0x60d7faed;
        vm.assertEq(fselector1, fselector2);
    }

    function test_Decode_CompleteQueuedWithdrawals_Array() public view {

        IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal[](2);
        {
            IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
            uint256[] memory sharesToWithdraw = new uint256[](1);

            strategiesToWithdraw[0] = strategy;
            sharesToWithdraw[0] = 0.00321 ether;

            withdrawals[0] = IDelegationManager.Withdrawal({
                staker: deployer,
                delegatedTo: address(0x0),
                withdrawer: deployer,
                nonce: 0,
                startBlock: uint32(block.number),
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw
            });
            withdrawals[1] = IDelegationManager.Withdrawal({
                staker: bob,
                delegatedTo: address(0x0),
                withdrawer: bob,
                nonce: 1,
                startBlock: uint32(block.number),
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw
            });
        }

        IERC20[][] memory tokensToWithdraw = new IERC20[][](2);
        {
            IERC20[] memory tokens1 = new IERC20[](2);
            tokens1[0] = IERC20(address(6));
            tokens1[1] = IERC20(address(7));
            IERC20[] memory tokens2 = new IERC20[](3);
            tokens2[0] = IERC20(address(8));
            tokens2[1] = IERC20(address(9));
            tokens2[2] = IERC20(address(5));
            tokensToWithdraw[0] = tokens1;
            tokensToWithdraw[1] = tokens2;
        }

        uint256[] memory middlewareTimesIndexes = new uint256[](2);
        bool[] memory receiveAsTokens = new bool[](2);

        middlewareTimesIndexes[0] = 0;
        middlewareTimesIndexes[1] = 1;
        receiveAsTokens[0] = true;
        receiveAsTokens[1] = false;

        bytes memory messageWithSignature_CW_Array;
        {
            messageWithSignature_CW_Array = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                encodeCompleteWithdrawalsMsg(
                    withdrawals,
                    tokensToWithdraw,
                    middlewareTimesIndexes,
                    receiveAsTokens
                ),
                execNonce,
                expiry
            );
        }

        (
            IDelegationManager.Withdrawal[] memory _withdrawals,
            IERC20[][] memory _tokensToWithdraw,
            uint256[] memory _middlewareTimesIndexes,
            bool[] memory _receiveAsTokens,
            address _signer,
            uint256 _expiry,
            bytes memory _signature
        ) = CompleteWithdrawalsArrayDecoder.decodeCompleteWithdrawalsMsg(
            abi.encode(string(
                messageWithSignature_CW_Array
            ))
        );

        vm.assertEq(_signature.length, 65);
        vm.assertEq(_signer, deployer);
        vm.assertEq(_expiry, expiry);

        vm.assertEq(_withdrawals[0].staker, withdrawals[0].staker);
        vm.assertEq(_withdrawals[0].withdrawer, withdrawals[0].withdrawer);
        vm.assertEq(_withdrawals[0].nonce, withdrawals[0].nonce);
        vm.assertEq(_withdrawals[0].startBlock, withdrawals[0].startBlock);
        vm.assertEq(address(_withdrawals[0].strategies[0]), address(withdrawals[0].strategies[0]));
        vm.assertEq(_withdrawals[0].shares[0], withdrawals[0].shares[0]);

        vm.assertEq(_withdrawals[1].staker, withdrawals[1].staker);
        vm.assertEq(_withdrawals[1].withdrawer, withdrawals[1].withdrawer);
        vm.assertEq(_withdrawals[1].nonce, withdrawals[1].nonce);
        vm.assertEq(_withdrawals[1].startBlock, withdrawals[1].startBlock);
        vm.assertEq(address(_withdrawals[1].strategies[0]), address(withdrawals[1].strategies[0]));
        vm.assertEq(_withdrawals[1].shares[0], withdrawals[1].shares[0]);

        vm.assertEq(address(_tokensToWithdraw[0][0]), address(tokensToWithdraw[0][0]));
        vm.assertEq(address(_tokensToWithdraw[0][1]), address(tokensToWithdraw[0][1]));

        vm.assertEq(address(_tokensToWithdraw[1][0]), address(tokensToWithdraw[1][0]));
        vm.assertEq(address(_tokensToWithdraw[1][1]), address(tokensToWithdraw[1][1]));
        vm.assertEq(address(_tokensToWithdraw[1][2]), address(tokensToWithdraw[1][2]));

        vm.assertEq(_middlewareTimesIndexes[0], middlewareTimesIndexes[0]);
        vm.assertEq(_middlewareTimesIndexes[1], middlewareTimesIndexes[1]);

        vm.assertEq(_receiveAsTokens[0], receiveAsTokens[0]);
        vm.assertEq(_receiveAsTokens[1], receiveAsTokens[1]);
    }

    function test_Decode_WithdrawalTransferToAgentOwnerMsg() public view {

        bytes32 withdrawalRoot = 0x8c20d3a37feccd4dcb9fa5fbd299b37db00fde77cbb7540e2850999fc7d8ec77;

        address bob = vm.addr(8881);
        bytes32 withdrawalTransferRoot = keccak256(abi.encode(withdrawalRoot, amount, bob));

        TransferToAgentOwnerMsg memory tta_msg = eigenlayerMsgDecoders.decodeTransferToAgentOwnerMsg(
            abi.encode(string(
                encodeTransferToAgentOwnerMsg(
                    calculateWithdrawalTransferRoot(
                        withdrawalRoot,
                        amount,
                        bob
                    )
                )
            ))
        );

        vm.assertEq(tta_msg.transferRoot, withdrawalTransferRoot);
    }

    function test_Decode_RewardTransferToAgentOwnerMsg() public view {

        bytes32 mockRewardsRoot = 0x999eeee37feccd4dcb9fa5fbd299b37db00fde77cbb7540e2850999fc7eeeeee;

        address bob = vm.addr(8881);
        uint256 rewardAmount = 1.5 ether;
        address rewardToken = address(tokenL1);
        address agentOwner = deployer;

        bytes32 rewardsTransferRoot = EigenlayerMsgEncoders.calculateRewardsTransferRoot(
            mockRewardsRoot,
            rewardAmount,
            rewardToken,
            agentOwner
        );

        TransferToAgentOwnerMsg memory tta_msg = eigenlayerMsgDecoders.decodeTransferToAgentOwnerMsg(
            abi.encode(string(
                encodeTransferToAgentOwnerMsg(
                    calculateRewardsTransferRoot(
                        mockRewardsRoot,
                        rewardAmount,
                        rewardToken,
                        agentOwner
                    )
                )
            ))
        );

        vm.assertEq(tta_msg.transferRoot, rewardsTransferRoot);
    }

    /*
     *
     *
     *                   Delegation
     *
     *
    */

    function test_Decode_DelegateTo() public {

        address eigenAgent = vm.addr(0x1);
        address operator = vm.addr(0x2);
        bytes32 approverSalt = 0x0000000000000000000000000000000000000000000000000000000000004444;
        execNonce = 0;
        uint256 sig1_expiry = block.timestamp + 50 minutes;

        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;
        {

            bytes32 digestHash1 = calculateDelegationApprovalDigestHash(
                eigenAgent,
                operator,
                operator,
                approverSalt,
                sig1_expiry,
                address(delegationManager),
                EthSepolia.ChainSelector
            );

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash1);
            bytes memory signature1 = abi.encodePacked(r, s, v);

            approverSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature1,
                expiry: sig1_expiry
            });
        }

        ///////////////////////////////////////
        /// Append EiggenAgent Signature
        ///////////////////////////////////////

        bytes memory message_DT;
        bytes memory messageWithSignature_DT;
        {
            message_DT = encodeDelegateTo(
                operator,
                approverSignatureAndExpiry,
                approverSalt
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_DT = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                message_DT,
                execNonce,
                sig1_expiry
            );
        }

        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(messageWithSignature_DT));

        (
            address _operator,
            ISignatureUtils.SignatureWithExpiry memory _approverSignatureAndExpiry,
            bytes32 _approverSalt,
            address _signer,
            , // uint256 _expiryEigenAgent
            // bytes memory _signatureEigenAgent
        ) = DelegationDecoders.decodeDelegateToMsg(message);

        vm.assertEq(operator, _operator);
        vm.assertEq(deployer, _signer);
        vm.assertEq(approverSalt, _approverSalt);

        vm.assertEq(approverSignatureAndExpiry.expiry, _approverSignatureAndExpiry.expiry);
        vm.assertEq(keccak256(approverSignatureAndExpiry.signature), keccak256(_approverSignatureAndExpiry.signature));
    }

    function test_Decode_Undelegate() public {

        address staker1 = vm.addr(0x1);
        execNonce = 0;
        expiry = block.timestamp + 1 hours;

        bytes memory message_UD;
        bytes memory messageWithSignature_UD;
        {
            message_UD = encodeUndelegateMsg(
                staker1
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_UD = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                message_UD,
                execNonce,
                expiry
            );
        }

        (
            address _staker1,
            address signer,
            uint256 expiryEigenAgent,
            // bytes memory signatureEigenAgent
        ) = DelegationDecoders.decodeUndelegateMsg(
            abi.encode(string(
                messageWithSignature_UD
            ))
        );

        vm.assertEq(staker1, _staker1);
        vm.assertEq(signer, deployer);
        vm.assertEq(expiry, expiryEigenAgent);
    }

    /*
     *
     *
     *                   Rewards Claims
     *
     *
    */

    function test_Decode_RewardsProcessClaim() public view {

        // struct RewardsMerkleClaim {
        //     uint32 rootIndex;
        //     uint32 earnerIndex;
        //     bytes earnerTreeProof;
        //     EarnerTreeMerkleLeaf earnerLeaf;
        //     uint32[] tokenIndices;
        //     bytes[] tokenTreeProofs;
        //     TokenTreeMerkleLeaf[] tokenLeaves;
        // }
        // struct EarnerTreeMerkleLeaf {
        //     address earner;
        //     bytes32 earnerTokenRoot;
        // }
        // struct TokenTreeMerkleLeaf {
        //     IERC20 token;
        //     uint256 cumulativeEarnings;
        // }

        // live example:
        // https://dashboard.tenderly.co/tx/holesky/0x0c6039e0fa7d6a0e32f4f62114a87fb1d5e4e37ff84dbdf9cc2d6c672d5af9de/debugger?trace=0.2
        bytes memory earnerTreeProof = hex"32c3756cc20bcbdb7f8b25dcb3b904ea271776626d79cf1797932298c3bc5c628a09335bd33183649a1338e1ce19dcc11b6e7500659b71ddeb3680855b6eeffdd879bbbe67f12fc80b7df9df2966012d54b23b2c1265c708cc64b12d38acf88a82277145d984d6a9dc5bdfa13cee09e543b810cef077330bd5828b746b8c92bb622731e95bf8721578fa6c5e1ceaf2e023edb2b9c989c7106af8455ceae4aaad1891758b2b17b58a3de5a98d61349658dd8b58bc3bfa5b08ec98ecf6bb45447bc45497275645c6cc432bf191633578079fc8787b0ee849e5af9c9a60375da395a8f7fbb5bc80c876748e5e000aedc8de1e163bbb930f5f05f49eafdfe43407e1daa8be3a9a68d8aeb17e55e562ae2d9efc90e3ced7e9992663a98c4309703e68728dfe1ec72d08c5516592581f81e8f2d8b703331bfd313ad2e343f9c7a3548821ed079b6f019319b2f7c82937cb24e1a2fde130b23d72b7451a152f71e8576abddb9b0b135ad963dba00860e04a76e8930a74a5513734e50c724b5bd550aa3f06e9d61d236796e70e35026ab17007b95d82293a2aecb1f77af8ee6b448abddb2ddce73dbc52aab08791998257aa5e0736d60e8f2d7ae5b50ef48971836435fd81a8556e13ffad0889903995260194d5330f98205b61e5c6555d8404f97d9fba8c1b83ea7669c5df034056ce24efba683a1303a3a0596997fa29a5028c5c2c39d6e9f04e75babdc9087f61891173e05d73f05da01c36d28e73c3b5594b61c107";

        bytes32 earnerTokenRoot = 0x899e3bde2c009bda46a51ecacd5b3f6df0af2833168cc21cac5f75e8c610ce0d;
        IRewardsCoordinator.EarnerTreeMerkleLeaf memory earnerLeaf = IRewardsCoordinator.EarnerTreeMerkleLeaf({
            earner: deployer,
            earnerTokenRoot: earnerTokenRoot
        });

        uint32[] memory tokenIndices = new uint32[](2);
        tokenIndices[0] = 0;
        tokenIndices[1] = 1;

        bytes[] memory tokenTreeProofs = new bytes[](2);
        tokenTreeProofs[0] = hex"30c06778aea3c632bc61f3a0ffa0b57bd9ce9c2cf76f9ad2369f1b46081bc90b";
        tokenTreeProofs[1] = hex"c82aa805d0910fc0a12610e7b59a440050529cf2a5b9e5478642bfa7f785fc79";

        IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves;
        tokenLeaves = new IRewardsCoordinator.TokenTreeMerkleLeaf[](2);
        tokenLeaves[0] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: IERC20(0x4Bd30dAf919a3f74ec57f0557716Bcc660251Ec0),
            cumulativeEarnings: 3919643917052950253556
        });
        tokenLeaves[1] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: IERC20(0xdeeeeE2b48C121e6728ed95c860e296177849932),
            cumulativeEarnings: 897463507533062629000000
        });

        IRewardsCoordinator.RewardsMerkleClaim memory claim = IRewardsCoordinator.RewardsMerkleClaim({
            rootIndex: 84, // uint32 rootIndex;
            earnerIndex: 66130, // uint32 earnerIndex;
            earnerTreeProof: earnerTreeProof, // bytes earnerTreeProof;
            earnerLeaf: earnerLeaf, // EarnerTreeMerkleLeaf earnerLeaf;
            tokenIndices: tokenIndices, // uint32[] tokenIndices;
            tokenTreeProofs: tokenTreeProofs, // bytes[] tokenTreeProofs;
            tokenLeaves: tokenLeaves // TokenTreeMerkleLeaf[] tokenLeaves;
        });

        address recipient = deployer;

        // sign the message for EigenAgent to execute Eigenlayer command
        bytes memory messageWithSignature_PC = signMessageForEigenAgentExecution(
            deployerKey,
            block.chainid, // destination chainid where EigenAgent lives
            address(123123), // StrategyManager to approve + deposit
            encodeProcessClaimMsg(claim, recipient),
            execNonce,
            expiry
        );

        (
            IRewardsCoordinator.RewardsMerkleClaim memory _claim,
            address _recipient,
            address _signer,
            uint256 _expiry,
            bytes memory _signature
        ) = eigenlayerMsgDecoders.decodeProcessClaimMsg(
            abi.encode(string(
                messageWithSignature_PC
            ))
        );

        vm.assertEq(claim.rootIndex, 84);
        vm.assertEq(claim.earnerIndex, 66130);
        require(keccak256(claim.earnerTreeProof) ==  keccak256(earnerTreeProof), "incorrect earnerTreeProof");
        vm.assertEq(claim.earnerLeaf.earner, deployer);
        vm.assertEq(claim.earnerLeaf.earnerTokenRoot, earnerTokenRoot);
        vm.assertEq(claim.tokenIndices[0], 0);
        vm.assertEq(claim.tokenIndices[1], 1);

        vm.assertEq(keccak256(claim.tokenTreeProofs[0]), keccak256(tokenTreeProofs[0]));
        vm.assertEq(keccak256(claim.tokenTreeProofs[1]), keccak256(tokenTreeProofs[1]));

        vm.assertEq(address(claim.tokenLeaves[0].token), address(tokenLeaves[0].token));
        vm.assertEq(claim.tokenLeaves[0].cumulativeEarnings, tokenLeaves[0].cumulativeEarnings);
        vm.assertEq(address(claim.tokenLeaves[1].token), address(tokenLeaves[1].token));
        vm.assertEq(claim.tokenLeaves[1].cumulativeEarnings, tokenLeaves[1].cumulativeEarnings);

        vm.assertEq(_signer, deployer);
        vm.assertEq(_expiry, expiry);
    }

    function test_Decode_RewardsProcessClaim_DynamicLengthProofs() public {
        // Trickier example where tokenTreeProofs (dynamic bytestrings) are uneven lengths.
        bytes32 earnerTokenRoot = 0x899e3bde2c009bda46a51ecacd5b3f6df0af2833168cc21cac5f75e8c610ce0d;
        IRewardsCoordinator.EarnerTreeMerkleLeaf memory earnerLeaf = IRewardsCoordinator.EarnerTreeMerkleLeaf({
            earner: deployer,
            earnerTokenRoot: earnerTokenRoot
        });

        uint32[] memory tokenIndices = new uint32[](2);
        tokenIndices[0] = 0;
        tokenIndices[1] = 1;

        IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves;
        tokenLeaves = new IRewardsCoordinator.TokenTreeMerkleLeaf[](2);
        tokenLeaves[0] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: IERC20(0x4Bd30dAf919a3f74ec57f0557716Bcc660251Ec0),
            cumulativeEarnings: 3919643917052950253556
        });
        tokenLeaves[1] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: IERC20(0xdeeeeE2b48C121e6728ed95c860e296177849932),
            cumulativeEarnings: 897463507533062629000000
        });

        address recipient = deployer;

        bytes[] memory tokenTreeProofs = new bytes[](3);
        // tokenTreeProofs are dynamic sized bytestrings, each a multiple of 32 bytes long.
        // we test three different lengnthed bytestrings for proofs:
        tokenTreeProofs[0] = hex"aaaaaa78aea3c632bc61f3a0ffa0b57bd666662cf76f9ad2369f1b46081aaaaaaaaaaa78aea3c632bc61f3a0ffa0111111ce9c2cf76f9ad2369f1b46081aaaaaaaaaaa78aea32222bc61f3a0ffa0b57bd9ce9c22226f9ad2369f1b46081aaaaa";
        tokenTreeProofs[1] = hex"bbbbbb05d0910fc0a12610e7b599999950529cf2a5b9e5478642bfa7f78bbbbb";
        tokenTreeProofs[2] = hex"cccccc05d0910fc0a12610e7b59a4400599999f2a5b9e5478642bfa7f785cccccccccc05d0910fc0a44440e7b59a440050529444a5b9e5478642bfa7f785cccc";
        bytes memory earnerTreeProof = hex"32c3756cc20bcbdb7f8b25dcb3b904ea271776626d79cf1797932298c3bc5c628a09335bd33183649a1338e1ce19dcc11b6e7500659b71ddeb3680855b6eeffdd879bbbe67f12fc80b7df9df2966012d54b23b2c1265c708cc64b12d38acf88a82277145d984d6a9dc5bdfa13cee09e543b810cef077330bd5828b746b8c92bb622731e95bf8721578fa6c5e1ceaf2e023edb2b9c989c7106af8455ceae4aaad1891758b2b17b58a3de5a98d61349658dd8b58bc3bfa5b08ec98ecf6bb45447bc45497275645c6cc432bf191633578079fc8787b0ee849e5af9c9a60375da395a8f7fbb5bc80c876748e5e000aedc8de1e163bbb930f5f05f49eafdfe43407e1daa8be3a9a68d8aeb17e55e562ae2d9efc90e3ced7e9992663a98c4309703e68728dfe1ec72d08c5516592581f81e8f2d8b703331bfd313ad2e343f9c7a3548821ed079b6f019319b2f7c82937cb24e1a2fde130b23d72b7451a152f71e8576abddb9b0b135ad963dba00860e04a76e8930a74a5513734e50c724b5bd550aa3f06e9d61d236796e70e35026ab17007b95d82293a2aecb1f77af8ee6b448abddb2ddce73dbc52aab08791998257aa5e0736d60e8f2d7ae5b50ef48971836435fd81a8556e13ffad0889903995260194d5330f98205b61e5c6555d8404f97d9fba8c1b83ea7669c5df034056ce24efba683a1303a3a0596997fa29a5028c5c2c39d6e9f04e75babdc9087f61891173e05d73f05da01c36d28e73c3b5594b61c107";

        IRewardsCoordinator.RewardsMerkleClaim memory claim = IRewardsCoordinator.RewardsMerkleClaim({
            rootIndex: 84, // uint32 rootIndex;
            earnerIndex: 66130, // uint32 earnerIndex;
            earnerTreeProof: earnerTreeProof, // bytes earnerTreeProof;
            earnerLeaf: earnerLeaf, // EarnerTreeMerkleLeaf earnerLeaf;
            tokenIndices: tokenIndices, // uint32[] tokenIndices;
            tokenTreeProofs: tokenTreeProofs, // bytes[] tokenTreeProofs;
            tokenLeaves: tokenLeaves // TokenTreeMerkleLeaf[] tokenLeaves;
        });

        bytes memory messageWithSignature_PC = signMessageForEigenAgentExecution(
            deployerKey,
            block.chainid, // destination chainid where EigenAgent lives
            address(123123), // StrategyManager to approve + deposit
            encodeProcessClaimMsg(claim, recipient),
            execNonce,
            expiry
        );

        (
            IRewardsCoordinator.RewardsMerkleClaim memory claim2,
            ,
            ,
            ,
        ) = eigenlayerMsgDecoders.decodeProcessClaimMsg(
            abi.encode(string(
                messageWithSignature_PC
            ))
        );

        vm.assertEq(keccak256(claim2.tokenTreeProofs[0]), keccak256(tokenTreeProofs[0]));
        vm.assertEq(keccak256(claim2.tokenTreeProofs[1]), keccak256(tokenTreeProofs[1]));
        vm.assertEq(keccak256(claim2.tokenTreeProofs[2]), keccak256(tokenTreeProofs[2]));
    }

    function test_Decode_RewardsProcessClaim_InvalidMerkleProofs() public {

        bytes32 earnerTokenRoot = 0x899e3bde2c009bda46a51ecacd5b3f6df0af2833168cc21cac5f75e8c610ce0d;
        IRewardsCoordinator.EarnerTreeMerkleLeaf memory earnerLeaf = IRewardsCoordinator.EarnerTreeMerkleLeaf({
            earner: deployer,
            earnerTokenRoot: earnerTokenRoot
        });

        uint32[] memory tokenIndices = new uint32[](2);
        tokenIndices[0] = 0;
        tokenIndices[1] = 1;

        IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves;
        tokenLeaves = new IRewardsCoordinator.TokenTreeMerkleLeaf[](2);
        tokenLeaves[0] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: IERC20(0x4Bd30dAf919a3f74ec57f0557716Bcc660251Ec0),
            cumulativeEarnings: 3919643917052950253556
        });
        tokenLeaves[1] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: IERC20(0xdeeeeE2b48C121e6728ed95c860e296177849932),
            cumulativeEarnings: 897463507533062629000000
        });

        address recipient = deployer;

        // try invalid tokenTreeProofs
        bytes memory messageWithSignature_PC;
        {
            bytes[] memory tokenTreeProofs = new bytes[](2);
            tokenTreeProofs[0] = hex"30c06778aea3c63230c06778aea3c632";
            tokenTreeProofs[1] = hex"c82aa805d0910fc0";
            bytes memory earnerTreeProof = hex"32c3756cc20bcbdb7f8b25dcb3b904ea271776626d79cf1797932298c3bc5c62";

            IRewardsCoordinator.RewardsMerkleClaim memory claim = IRewardsCoordinator.RewardsMerkleClaim({
                rootIndex: 84, // uint32 rootIndex;
                earnerIndex: 66130, // uint32 earnerIndex;
                earnerTreeProof: earnerTreeProof, // bytes earnerTreeProof;
                earnerLeaf: earnerLeaf, // EarnerTreeMerkleLeaf earnerLeaf;
                tokenIndices: tokenIndices, // uint32[] tokenIndices;
                tokenTreeProofs: tokenTreeProofs, // bytes[] tokenTreeProofs;
                tokenLeaves: tokenLeaves // TokenTreeMerkleLeaf[] tokenLeaves;
            });

            messageWithSignature_PC = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                encodeProcessClaimMsg(claim, recipient),
                execNonce,
                expiry
            );

            vm.expectRevert("tokenTreeProof length must be a multiple of 32");
            eigenlayerMsgDecoders.decodeProcessClaimMsg(
                abi.encode(string(
                    messageWithSignature_PC
                ))
            );
        }

        // try invalid earnerTreeProof
        {
            bytes[] memory tokenTreeProofs2 = new bytes[](2);
            tokenTreeProofs2[0] = hex"30c06778aea3c632bc61f3a0ffa0b57bd9ce9c2cf76f9ad2369f1b46081bc90b";
            tokenTreeProofs2[1] = hex"c82aa805d0910fc0a12610e7b59a440050529cf2a5b9e5478642bfa7f785fc79";
            bytes memory earnerTreeProof2 = hex"33";

            IRewardsCoordinator.RewardsMerkleClaim memory claim2 = IRewardsCoordinator.RewardsMerkleClaim({
                rootIndex: 84, // uint32 rootIndex;
                earnerIndex: 66130, // uint32 earnerIndex;
                earnerTreeProof: earnerTreeProof2, // bytes earnerTreeProof;
                earnerLeaf: earnerLeaf, // EarnerTreeMerkleLeaf earnerLeaf;
                tokenIndices: tokenIndices, // uint32[] tokenIndices;
                tokenTreeProofs: tokenTreeProofs2, // bytes[] tokenTreeProofs;
                tokenLeaves: tokenLeaves // TokenTreeMerkleLeaf[] tokenLeaves;
            });

            messageWithSignature_PC = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(123123), // StrategyManager to approve + deposit
                encodeProcessClaimMsg(claim2, recipient),
                execNonce,
                expiry
            );

            vm.expectRevert("earnerTreeProofLength must be divisible by 32");
            eigenlayerMsgDecoders.decodeProcessClaimMsg(
                abi.encode(string(
                    messageWithSignature_PC
                ))
            );
        }
    }

}
