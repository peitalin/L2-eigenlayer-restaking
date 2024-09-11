// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    EigenlayerMsgDecoders,
    DelegationDecoders,
    AgentOwnerSignature,
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
        require(functionSelector1 == 0xf7e784ef, "wrong functionSelector");

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
        require(functionSelector2 == 0x32e89ace, "wrong functionSelector");
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
        require(_signer == vm.addr(deployerKey), "decodeAgentOwnerSignature: signer not original address");
        require(_expiry == expiry, "decodeAgentOwnerSignature: expiry not original expiry");
        require(_amount == amount, "decodeAgentOwnerSignature: amount not original amount");
        require(_token == address(tokenL1), "decodeAgentOwnerSignature: token not original tokenL1");
        require(_strategy == address(strategy), "decodeAgentOwnerSignature: strategy not original strategy");

        // compare decodeAgentOwner vs decodeDepositIntoStrategy
        require(_signer == _signer2, "decodeAgentOwnerSignature: signer did not match");
        require(_expiry == _expiry2, "decodeAgentOwnerSignature: expiry did not match");
        require(
            keccak256(_signature) == keccak256(_signature2),
            "decodeAgentOwnerSignature: signature incorrect"
        );
    }

    function test_Decode_MintEigenAgent() public view {

        // use EigenlayerMsgEncoders for coverage.
        bytes memory messageToMint = EigenlayerMsgEncoders.encodeMintEigenAgent(staker);
        // CCIP turns the message into string when sending
        bytes memory messageCCIP = abi.encode(string(messageToMint));

        address recipient = eigenlayerMsgDecoders.decodeMintEigenAgent(messageCCIP);

        require(recipient == staker, "mintEigenAgent: staker does not match");
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

        require(address(_strategy) == address(strategy), "strategy does not match");
        require(address(tokenL1) == _token, "token error: decodeDepositIntoStrategyMsg");
        require(amount == _amount, "amount error: decodeDepositIntoStrategyMsg");

        require(_signature.length == 65, "invalid signature length");
        require(_signer == staker, "staker does not match");
        require(expiry == _expiry, "expiry error: decodeDepositIntoStrategyMsg");
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
        IStrategy[] memory strategiesToWithdraw1 = new IStrategy[](1);
        IStrategy[] memory strategiesToWithdraw2 = new IStrategy[](1);

        uint256[] memory sharesToWithdraw0 = new uint256[](1);
        uint256[] memory sharesToWithdraw1 = new uint256[](1);
        uint256[] memory sharesToWithdraw2 = new uint256[](1);

        strategiesToWithdraw0[0] = IStrategy(0xb111111AD20E9d85d5152aE68f45f40A11111111);
        strategiesToWithdraw1[0] = IStrategy(0xb222222AD20e9D85d5152ae68F45f40a22222222);
        strategiesToWithdraw2[0] = IStrategy(0xb333333AD20e9D85D5152aE68f45F40A33333333);

        sharesToWithdraw0[0] = 0.010101 ether;
        sharesToWithdraw1[0] = 0.020202 ether;
        sharesToWithdraw2[0] = 0.030303 ether;

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
        require(_signature.length == 65, "signature bad length: decodeQueueWithdrawalsMsg");
        require(signer == deployer, "incorrect signer: decodeQueueWithdrawalsMsg");
        require(expiry == expiry2, "incorrect decoding: decodeQueueWithdrawalsMsg");
        // strategies
        require(
            decodedQW[2].strategies[0] == strategiesToWithdraw2[0],
            "incorrect decoding: decodeQueueWithdrawalsMsg[2]: strategies"
        );
        // shares
        require(
            decodedQW[0].shares[0] == sharesToWithdraw0[0],
            "incorrect decoding: decodeQueueWithdrawalsMsg[0]: shares"
        );
        require(
            decodedQW[1].shares[0] == sharesToWithdraw1[0],
            "incorrect decoding: decodeQueueWithdrawalsMsg[1]: shares"
        );
        // withdrawers
        require(
            decodedQW[0].withdrawer == QWPArray[0].withdrawer,
            "incorrect decoding: decodeQueueWithdrawalsMsg[0]: withdrawer"
        );
        require(
            decodedQW[1].withdrawer == QWPArray[1].withdrawer,
            "incorrect decoding: decodeQueueWithdrawalsMsg[1]: withdrawer"
        );
        require(
            decodedQW[2].withdrawer == QWPArray[2].withdrawer,
            "incorrect decoding: decodeQueueWithdrawalsMsg[2]: withdrawer"
        );
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

    function test_Decode_CompleteQueuedWithdrawal() public view {

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

        require(_signature.length == 65, "signature incorrect length: decodeCompleteWithdrawalsMsg");
        require(_signer == deployer, "incorrect signer: decodeCompleteWithdrawalsMsg");
        require(_expiry == expiry, "incorrect expiry: decodeCompleteWithdrawalsMsg");

        require(_withdrawal.shares[0] == withdrawal.shares[0], "decodeCompleteWithdrawalMsg shares error");
        require(_withdrawal.staker == withdrawal.staker, "decodeCompleteWithdrawalMsg staker error");
        require(_withdrawal.withdrawer == withdrawal.withdrawer, "decodeCompleteWithdrawalMsg withdrawer error");
        require(address(_tokensToWithdraw[0]) == address(tokensToWithdraw[0]), "decodeCompleteWithdrawalMsg tokensToWithdraw error");
        require(_receiveAsTokens == receiveAsTokens, "decodeCompleteWithdrawalMsg error");
    }

    function test_FunctionSelectors_CompleteQueueWithdrawal() public pure {
        bytes4 fselector1 = IDelegationManager.completeQueuedWithdrawal.selector;
        bytes4 fselector2 = bytes4(keccak256("completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],uint256,bool)"));
        // bytes4 fselector3 = 0x60d7faed;
        require(fselector1 == fselector2, "function selectors incorrect: completeQueuedWithdrawal");
    }

    function test_Decode_TransferToAgentOwnerMsg() public view {

        bytes32 withdrawalRoot = 0x8c20d3a37feccd4dcb9fa5fbd299b37db00fde77cbb7540e2850999fc7d8ec77;

        address bob = vm.addr(8881);
        bytes32 withdrawalTransferRoot = keccak256(abi.encode(withdrawalRoot, amount, bob));

        TransferToAgentOwnerMsg memory tta_msg = eigenlayerMsgDecoders.decodeTransferToAgentOwnerMsg(
            abi.encode(string(
                encodeHandleTransferToAgentOwnerMsg(
                    calculateWithdrawalTransferRoot(
                        withdrawalRoot,
                        amount,
                        bob
                    )
                )
            ))
        );

        require(tta_msg.withdrawalTransferRoot == withdrawalTransferRoot, "incorrect withdrawalTransferRoot");
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

        require(operator == _operator, "operator incorrect");
        require(deployer == _signer, "signer incorrect");
        require(approverSalt == _approverSalt, "approverSalt incorrect");

        require(
            approverSignatureAndExpiry.expiry == _approverSignatureAndExpiry.expiry,
            "approver signature expiry incorrect"
        );
        require(
            keccak256(approverSignatureAndExpiry.signature) == keccak256(_approverSignatureAndExpiry.signature),
            "approver signature incorrect"
        );
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

        require(staker1 == _staker1, "staker incorrect");
        require(signer == deployer, "signer incorrect");
        require(expiry == expiryEigenAgent, "signature expiry incorrect");
    }
}
