// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TransferToAgentOwnerMsg} from "../src/utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EigenlayerMsgDecoders} from "../src/utils/EigenlayerMsgDecoders.sol";
import {DelegationDecoders} from "../src/utils/DelegationDecoders.sol";
import {FunctionSelectorDecoder} from "../src/FunctionSelectorDecoder.sol";

import {ClientSigners} from "../script/ClientSigners.sol";
import {EthSepolia} from "../script/Addresses.sol";
import {FileReader} from "../script/FileReader.sol";


contract EigenlayerMsg_EncodingDecodingTests is Test {

    ClientSigners public signatureUtils;
    EigenlayerMsgDecoders public eigenlayerMsgDecoders;

    IStrategy public strategy;
    IERC20 public token;

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    uint256 amount;
    address staker;
    uint256 expiry;
    uint256 execNonce;

    function setUp() public {

        signatureUtils = new ClientSigners();
        eigenlayerMsgDecoders = new EigenlayerMsgDecoders();

        // just for deserializing, not calling these contracts
        strategy = IStrategy(0xBd4bcb3AD20E9d85D5152aE68F45f40aF8952159);
        token = IERC20(0x3Eef6ec7a9679e60CC57D9688E9eC0e6624D687A);
        amount = 0.0077 ether;
        staker = deployer;
        expiry = 86421;
        execNonce = 0;
    }

    function test_DecodeFunctionSelectors() public view {

        bytes memory message1 = hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000044f7e784ef00000000000000000000000000000000000000000000000000000000000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c00000000000000000000000000000000000000000000000000000000";
        bytes4 functionSelector1 = FunctionSelectorDecoder.decodeFunctionSelector(message1);
        require(functionSelector1 == 0xf7e784ef, "wrong functionSelector");

        bytes memory message2 = abi.encode(string(abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")),
            expiry,
            address(strategy),
            address(token),
            amount,
            staker,
            hex"3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c"
        )));
        bytes4 functionSelector2 = FunctionSelectorDecoder.decodeFunctionSelector(message2);
        require(functionSelector2 == 0x32e89ace, "wrong functionSelector");
    }

    /*
     *
     *
     *                   Deposits
     *
     *
    */

    function test_Decode_DepositIntoStrategy6551Msg() public view {

        bytes memory messageToEigenlayer = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
            address(strategy),
            address(token),
            amount
        );

        bytes memory messageWithSignature = signatureUtils.signMessageForEigenAgentExecution(
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
        ) = eigenlayerMsgDecoders.decodeDepositWithSignature6551Msg(messageWithSignatureCCIP);

        require(_signature.length == 65, "invalid signature length");
        require(_signer == staker, "staker does not match");
        require(expiry == _expiry, "expiry error: decodeDepositWithSignature6551Msg");

        require(address(_strategy) == address(strategy), "strategy does not match");
        require(address(token) == _token, "token error: decodeDepositWithSignature6551Msg");
        require(amount == _amount, "amount error: decodeDepositWithSignature6551Msg");
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
            message_QW = EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(
                QWPArray
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_QW = signatureUtils.signMessageForEigenAgentExecution(
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

        // console.log("[0].strategies[0]");
        // console.log(address(decodedQW[0].strategies[0]));
        // console.log("[0].shares[0]");
        // console.log(decodedQW[0].shares[0]);
        // console.log("[0].withdrawer");
        // console.log(decodedQW[0].withdrawer);

        // console.log("[1].strategies[0]");
        // console.log(address(decodedQW[1].strategies[0]));
        // console.log("[1].shares[0]");
        // console.log(decodedQW[1].shares[0]);
        // console.log("[1].withdrawer");
        // console.log(decodedQW[1].withdrawer);

        // console.log("[2].strategies[0]");
        // console.log(address(decodedQW[2].strategies[0]));
        // console.log("[2].shares[0]");
        // console.log(decodedQW[2].shares[0]);
        // console.log("[2].withdrawer");
        // console.log(decodedQW[2].withdrawer);

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
        tokensToWithdraw[0] = token;
        uint256 middlewareTimesIndex = 0; // not used, used when slashing is enabled;
        bool receiveAsTokens = true;

        bytes memory message_CW;
        bytes memory messageWithSignature_CW;
        {
            message_CW = EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                middlewareTimesIndex,
                receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = signatureUtils.signMessageForEigenAgentExecution(
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
            uint256 _middlewareTimesIndex,
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

        bytes32 withdrawalRoot1 = 0x8c20d3a37feccd4dcb9fa5fbd299b37db00fde77cbb7540e2850999fc7d8ec77;
        address agentOwner = vm.addr(0x02);

        TransferToAgentOwnerMsg memory tta_msg = eigenlayerMsgDecoders.decodeTransferToAgentOwnerMsg(
            abi.encode(string(
                EigenlayerMsgEncoders.encodeHandleTransferToAgentOwnerMsg(
                    withdrawalRoot1,
                    agentOwner
                )
            ))
        );

        require(tta_msg.withdrawalRoot == withdrawalRoot1, "incorrect withdrawalRoot");
    }

    /*
     *
     *
     *                   Delegation
     *
     *
    */

    function test_Decode_DelegateToBySignature_BothSigned() public view {

        address staker1 = vm.addr(0x1);
        address operator = vm.addr(0x2);
        address delegationManager = vm.addr(0xde);

        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry;
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;

        bytes memory signature1;
        bytes memory signature2;
        {
            uint256 sig1_expiry = 5;
            uint256 sig2_expiry = 6;

            bytes32 digestHash1 = signatureUtils.calculateStakerDelegationDigestHash(
                staker1,
                0,  // nonce
                operator,
                sig1_expiry,
                delegationManager,
                EthSepolia.ChainSelector
            );
            bytes32 digestHash2 = signatureUtils.calculateStakerDelegationDigestHash(
                staker,
                0,  // nonce
                operator,
                sig2_expiry,
                delegationManager,
                EthSepolia.ChainSelector
            );

            (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(deployerKey, digestHash1);
            (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(deployerKey, digestHash2);
            signature1 = abi.encodePacked(r1, s1, v1);
            signature2 = abi.encodePacked(r2, s2, v2);

            stakerSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature1,
                expiry: sig1_expiry
            });
            approverSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature2,
                expiry: sig2_expiry
            });
        }

        bytes32 approverSalt = 0x0000000000000000000000000000000000000000000000000000000000004444;

        bytes memory message_bytes = EigenlayerMsgEncoders.encodeDelegateToBySignature(
            staker1,
            operator,
            stakerSignatureAndExpiry,
            approverSignatureAndExpiry,
            approverSalt
        );
        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));

        (
            address _staker,
            address _operator,
            ISignatureUtils.SignatureWithExpiry memory _stakerSignatureAndExpiry,
            ISignatureUtils.SignatureWithExpiry memory _approverSignatureAndExpiry,
            bytes32 _approverSalt
        ) = DelegationDecoders.decodeDelegateToBySignatureMsg(message);

        require(staker1 == _staker, "staker incorrect");
        require(operator == _operator, "operator incorrect");
        require(approverSalt == _approverSalt, "approverSalt incorrect");

        require(
            stakerSignatureAndExpiry.expiry == _stakerSignatureAndExpiry.expiry,
            "staker signature expiry incorrect"
        );
        require(
            keccak256(stakerSignatureAndExpiry.signature) == keccak256(_stakerSignatureAndExpiry.signature),
            "staker signature incorrect"
        );
        require(
            approverSignatureAndExpiry.expiry == _approverSignatureAndExpiry.expiry,
            "approver signature expiry incorrect"
        );
        require(
            keccak256(approverSignatureAndExpiry.signature) == keccak256(_approverSignatureAndExpiry.signature),
            "approver signature incorrect"
        );
    }

    function test_Decode_DelegateToBySignature_Unsigned() public view {

        address staker1 = vm.addr(0x1);
        address operator = vm.addr(0x2);

        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry;
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;

        stakerSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
            signature: new bytes(0),
            expiry: 5
        });
        approverSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
            signature: new bytes(0),
            expiry: 6
        });

        bytes32 approverSalt = 0x0000000000000000000000000000000000000000000000000000000000004444;

        bytes memory message_bytes = EigenlayerMsgEncoders.encodeDelegateToBySignature(
            staker1,
            operator,
            stakerSignatureAndExpiry,
            approverSignatureAndExpiry,
            approverSalt
        );
        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));

        (
            address _staker,
            address _operator,
            ISignatureUtils.SignatureWithExpiry memory _stakerSignatureAndExpiry,
            ISignatureUtils.SignatureWithExpiry memory _approverSignatureAndExpiry,
            bytes32 _approverSalt
        ) = DelegationDecoders.decodeDelegateToBySignatureMsg(message);

        require(staker1 == _staker, "staker incorrect");
        require(operator == _operator, "operator incorrect");
        require(approverSalt == _approverSalt, "approverSalt incorrect");
        require(
            stakerSignatureAndExpiry.expiry == _stakerSignatureAndExpiry.expiry,
            "staker signature expiry incorrect"
        );
        require(
            keccak256(stakerSignatureAndExpiry.signature) == keccak256(_stakerSignatureAndExpiry.signature),
            "staker signature incorrect"
        );
        require(
            approverSignatureAndExpiry.expiry == _approverSignatureAndExpiry.expiry,
            "approver signature expiry incorrect"
        );
        require(
            keccak256(approverSignatureAndExpiry.signature) == keccak256(_approverSignatureAndExpiry.signature),
            "approver signature incorrect"
        );
    }

    function test_Decode_DelegateToBySignature_StakerSigned() public view {

        address staker1 = vm.addr(0x1);
        address operator = vm.addr(0x2);
        address delegationManager = vm.addr(0xde);

        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry;
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;

        bytes memory signature1;
        {
            uint256 sig1_expiry = 5;

            bytes32 digestHash1 = signatureUtils.calculateStakerDelegationDigestHash(
                staker,
                0,  // nonce
                operator,
                sig1_expiry,
                delegationManager,
                EthSepolia.ChainSelector
            );

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash1);
            signature1 = abi.encodePacked(r, s, v);

            console.logBytes(signature1);

            stakerSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature1,
                expiry: sig1_expiry
            });
            approverSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: new bytes(0),
                expiry: 6
            });
        }

        bytes32 approverSalt = 0x0000000000000000000000000000000000000000000000000000000000004444;

        bytes memory message_bytes = EigenlayerMsgEncoders.encodeDelegateToBySignature(
            staker1,
            operator,
            stakerSignatureAndExpiry,
            approverSignatureAndExpiry,
            approverSalt
        );
        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));

        (
            address _staker,
            address _operator,
            ISignatureUtils.SignatureWithExpiry memory _stakerSignatureAndExpiry,
            ISignatureUtils.SignatureWithExpiry memory _approverSignatureAndExpiry,
            bytes32 _approverSalt
        ) = DelegationDecoders.decodeDelegateToBySignatureMsg(message);

        require(staker1 == _staker, "staker incorrect");
        require(operator == _operator, "operator incorrect");
        require(approverSalt == _approverSalt, "approverSalt incorrect");

        require(
            stakerSignatureAndExpiry.expiry == _stakerSignatureAndExpiry.expiry,
            "staker signature expiry incorrect"
        );
        require(
            keccak256(stakerSignatureAndExpiry.signature) == keccak256(_stakerSignatureAndExpiry.signature),
            "staker signature incorrect"
        );
        require(
            approverSignatureAndExpiry.expiry == _approverSignatureAndExpiry.expiry,
            "approver signature expiry incorrect"
        );
        require(
            keccak256(approverSignatureAndExpiry.signature) == keccak256(_approverSignatureAndExpiry.signature),
            "approver signature incorrect"
        );
    }

    function test_Decode_DelegateToBySignature_ApproverSigned() public view {

        address staker1 = vm.addr(0x1);
        address operator = vm.addr(0x2);
        address delegationManager = vm.addr(0xde);

        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry;
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;

        bytes memory signature1;
        {
            uint256 sig1_expiry = 6;

            bytes32 digestHash1 = signatureUtils.calculateStakerDelegationDigestHash(
                staker1,
                0,  // nonce
                operator,
                sig1_expiry,
                delegationManager,
                EthSepolia.ChainSelector
            );

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash1);
            signature1 = abi.encodePacked(r, s, v);

            console.logBytes(signature1);

            stakerSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: new bytes(0),
                expiry: 5
            });
            approverSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature1,
                expiry: sig1_expiry
            });
        }

        bytes32 approverSalt = 0x0000000000000000000000000000000000000000000000000000000000004444;

        bytes memory message_bytes = EigenlayerMsgEncoders.encodeDelegateToBySignature(
            staker1,
            operator,
            stakerSignatureAndExpiry,
            approverSignatureAndExpiry,
            approverSalt
        );
        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));

        (
            address _staker,
            address _operator,
            ISignatureUtils.SignatureWithExpiry memory _stakerSignatureAndExpiry,
            ISignatureUtils.SignatureWithExpiry memory _approverSignatureAndExpiry,
            bytes32 _approverSalt
        ) = DelegationDecoders.decodeDelegateToBySignatureMsg(message);

        require(staker1 == _staker, "staker incorrect");
        require(operator == _operator, "operator incorrect");
        require(approverSalt == _approverSalt, "approverSalt incorrect");

        require(
            stakerSignatureAndExpiry.expiry == _stakerSignatureAndExpiry.expiry,
            "staker signature expiry incorrect"
        );
        require(
            keccak256(stakerSignatureAndExpiry.signature) == keccak256(_stakerSignatureAndExpiry.signature),
            "staker signature incorrect"
        );
        require(
            approverSignatureAndExpiry.expiry == _approverSignatureAndExpiry.expiry,
            "approver signature expiry incorrect"
        );
        require(
            keccak256(approverSignatureAndExpiry.signature) == keccak256(_approverSignatureAndExpiry.signature),
            "approver signature incorrect"
        );
    }

    function test_Decode_Undelegate() public view {

        address staker1 = vm.addr(0x1);

        address _staker = DelegationDecoders.decodeUndelegateMsg(
            abi.encode(string(
                EigenlayerMsgEncoders.encodeUndelegateMsg(staker1)
            ))
        );

        require(staker1 == _staker, "staker incorrect");
    }
}
