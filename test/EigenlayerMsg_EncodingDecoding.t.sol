// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {
    EigenlayerDepositParams,
    EigenlayerDepositMessage,
    EigenlayerDepositWithSignatureMessage,
    TransferToStakerMessage
} from "../src/interfaces/IEigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {FunctionSelectorDecoder} from "../src/FunctionSelectorDecoder.sol";

import {RestakingConnector} from "../src/RestakingConnector.sol";
import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EthSepolia} from "../script/Addresses.sol";
import {FileReader} from "../script/FileReader.sol";




contract EigenlayerMsg_EncodingDecodingTests is Test {

    uint256 public deployerKey;
    address public deployer;

    SignatureUtilsEIP1271 public signatureUtils;
    FileReader public fileReader;

    RestakingConnector public restakingConnector;
    IReceiverCCIP public receiverContract;
    IStrategy public strategy;
    IERC20 public token;
    uint256 amount;
    address staker;
    uint256 expiry;

    function setUp() public {
		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        restakingConnector = new RestakingConnector();
        signatureUtils = new SignatureUtilsEIP1271();
        fileReader = new FileReader();

        (receiverContract,) = fileReader.getReceiverRestakingConnectorContracts();

        // just for deserializing, not calling these contracts
        strategy = IStrategy(0xBd4bcb3AD20E9d85D5152aE68F45f40aF8952159);
        token = IERC20(0x3Eef6ec7a9679e60CC57D9688E9eC0e6624D687A);
        amount = 0.0077 ether;
        staker = address(0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c);
        expiry = 86421;
    }

    function test_DecodeFunctionSelectors() public {

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

    function test_Encodes_DepositWithSignature() public {

        amount = 0.0077 ether;
        bytes memory signature = hex"3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c";

        bytes memory messageBytes = abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")),
            address(strategy),
            address(token),
            amount,
            staker,
            expiry,
            signature
        );
        bytes memory messageBytes2 = EigenlayerMsgEncoders.encodeDepositIntoStrategyWithSignatureMsg(
            address(strategy),
            address(token),
            amount,
            staker,
            expiry,
            signature
        );

        require(
            keccak256(messageBytes) == keccak256(messageBytes2),
            "encoding from encodeDepositIntoStrategyWithSignatureMsg() did not match"
        );
    }

    function test_Decode_DepositWithSignature() public {

        bytes memory message_bytes = EigenlayerMsgEncoders.encodeDepositIntoStrategyWithSignatureMsg(
            address(strategy),
            address(token),
            amount,
            staker,
            expiry,
            hex"3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c"
        ); // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));

        EigenlayerDepositWithSignatureMessage memory depositMsg =
            restakingConnector.decodeDepositWithSignatureMessage(message);

        require(depositMsg.signature.length == 65, "invalid signature length");
        require(depositMsg.staker == staker, "staker does not match");
        require(address(depositMsg.strategy) == address(strategy), "strategy does not match");
    }

    function test_Decode_RevertBadSignature_DepositWithSignature() public {

        bytes memory signature = new bytes(0);

        bytes memory message_bytes = EigenlayerMsgEncoders.encodeDepositIntoStrategyWithSignatureMsg(
            address(strategy),
            address(token),
            amount,
            staker,
            expiry,
            signature
        ); // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));

        vm.expectRevert("decodeDepositWithSignatureMessage: invalid signature length");
        EigenlayerDepositWithSignatureMessage memory depositMsg =
            restakingConnector.decodeDepositWithSignatureMessage(message);
    }

    /*
     *
     *
     *                   Queue Withdrawals
     *
     *
    */

    function test_Decode_QueueWithdrawals() public view {

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);
        IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal;

        uint256 stakerShares = 0.00123 ether;
        address withdrawer = deployer;

        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = stakerShares;
        queuedWithdrawal = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw,
            withdrawer: withdrawer
        });

        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams;
        queuedWithdrawalParams = new IDelegationManager.QueuedWithdrawalParams[](1);
        queuedWithdrawalParams[0] = queuedWithdrawal;

        bytes memory message_bytes = EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(
            queuedWithdrawalParams
        );
        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));

        ////////////////////////////////////////////////////////
        //// Message payload offsets for assembly decoding
        ////////////////////////////////////////////////////////
        // Function Signature:
        //     bytes4(keccak256("queueWithdrawals((address[],uint256[],address)[])")),
        // Params:
        //     queuedWithdrawal = IDelegationManager.QueuedWithdrawalParams({
        //         strategies: strategiesToWithdraw,
        //         shares: sharesToWithdraw,
        //         withdrawer: withdrawer
        //     });

        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 0000000000000000000000000000000000000000000000000000000000000144 [64] string length
        // 0dd8dd02                                                         [96] function selector
        // 0000000000000000000000000000000000000000000000000000000000000020 [100] array offset
        // 0000000000000000000000000000000000000000000000000000000000000001 [132] array length
        // 0000000000000000000000000000000000000000000000000000000000000020 [164] struct offset: QueuedWithdrawalParams (3 fields)
        // 0000000000000000000000000000000000000000000000000000000000000060 [196] - 1st field offset: 96 bytes (3 rows down)
        // 00000000000000000000000000000000000000000000000000000000000000a0 [228] - 2nd field offset: 160 bytes (5 rows down)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [260] - 3rd field is static: withdrawer address
        // 0000000000000000000000000000000000000000000000000000000000000001 [292] - 1st field `strategies` is dynamic array of length: 1
        // 000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40af8952159 [324]     - value of strategies[0]
        // 0000000000000000000000000000000000000000000000000000000000000001 [356] - 2nd field `shares` is dynamic array of length: 1
        // 00000000000000000000000000000000000000000000000000045eadb112e000 [388]     - value of shares[0]
        // 00000000000000000000000000000000000000000000000000000000

        bytes32 _str_offset;
        bytes32 _str_length;
        bytes4 functionSelector;

        bytes32 _arrayOffset;
        bytes32 _arrayLength;

        bytes32 _structOffset;
        bytes32 _structField1Offset;
        bytes32 _structField2Offset;

        address _withdrawer;
        bytes32 _structField1ArrayLength;
        address _strategy;
        bytes32 _structField2ArrayLength;
        uint256 _sharesToWithdraw;

        assembly {
            _str_offset := mload(add(message, 32))
            _str_length := mload(add(message, 64))
            functionSelector := mload(add(message, 96))

            _arrayOffset := mload(add(message, 100))
            _arrayLength := mload(add(message, 132))
            _structOffset := mload(add(message, 164))
            _structField1Offset := mload(add(message, 196))
            _structField2Offset := mload(add(message, 228))
            _withdrawer := mload(add(message, 260))
            _structField1ArrayLength := mload(add(message, 292))
            _strategy := mload(add(message, 324))
            _structField2ArrayLength := mload(add(message, 356))
            _sharesToWithdraw := mload(add(message, 388))
        }

        require(_withdrawer == queuedWithdrawalParams[0].withdrawer, "decoded withdrawer incorrect");
        require(_sharesToWithdraw == queuedWithdrawalParams[0].shares[0], "decoded shares incorrect");
        require(_strategy == address(queuedWithdrawalParams[0].strategies[0]), "decoded strategy incorrect");
    }

    function test_Decode_Array_QueueWithdrawals() public {

        IStrategy[] memory strategiesToWithdraw1 = new IStrategy[](1);
        IStrategy[] memory strategiesToWithdraw2 = new IStrategy[](1);
        IStrategy[] memory strategiesToWithdraw3 = new IStrategy[](1);

        uint256[] memory sharesToWithdraw1 = new uint256[](1);
        uint256[] memory sharesToWithdraw2 = new uint256[](1);
        uint256[] memory sharesToWithdraw3 = new uint256[](1);

        IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal1;
        IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal2;
        IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal3;

        strategiesToWithdraw1[0] = IStrategy(0xb111111AD20E9d85d5152aE68f45f40A11111111);
        strategiesToWithdraw2[0] = IStrategy(0xb222222AD20e9D85d5152ae68F45f40a22222222);
        strategiesToWithdraw3[0] = IStrategy(0xb333333AD20e9D85D5152aE68f45F40A33333333);

        sharesToWithdraw1[0] = 0.010101 ether;
        sharesToWithdraw2[0] = 0.020202 ether;
        sharesToWithdraw3[0] = 0.030303 ether;

        queuedWithdrawal1 = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategiesToWithdraw1,
            shares: sharesToWithdraw1,
            withdrawer: deployer
        });
        queuedWithdrawal2 = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategiesToWithdraw2,
            shares: sharesToWithdraw2,
            withdrawer: vm.addr(0x2)
        });
        queuedWithdrawal3 = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategiesToWithdraw3,
            shares: sharesToWithdraw3,
            withdrawer: vm.addr(0x3)
        });

        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams3 =
            new IDelegationManager.QueuedWithdrawalParams[](3);
        queuedWithdrawalParams3[0] = queuedWithdrawal1;
        queuedWithdrawalParams3[1] = queuedWithdrawal2;
        queuedWithdrawalParams3[2] = queuedWithdrawal3;

        bytes memory message3 = abi.encode(string(
            EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(
                queuedWithdrawalParams3
            )
        ));

        IDelegationManager.QueuedWithdrawalParams[] memory decodedQueuedWithdrawals;
        decodedQueuedWithdrawals = restakingConnector.decodeQueueWithdrawalsMessage(message3);

        require(
            decodedQueuedWithdrawals[0].shares[0] == sharesToWithdraw1[0],
            "incorrect decoding: decodeQueueWithdrawalsArrayMessage"
        );
        require(
            decodedQueuedWithdrawals[1].shares[0] == sharesToWithdraw2[0],
            "incorrect decoding: decodeQueueWithdrawalsArrayMessage"
        );
        require(
            decodedQueuedWithdrawals[2].shares[0] == sharesToWithdraw3[0],
            "incorrect decoding: decodeQueueWithdrawalsArrayMessage"
        );
    }


    function test_Decode_Array_QueueWithdrawalsWithSignature() public {

        IStrategy[] memory strategiesToWithdraw1 = new IStrategy[](1);
        strategiesToWithdraw1[0] = strategy;

        uint256[] memory sharesToWithdraw1 = new uint256[](1);
        sharesToWithdraw1[0] = amount;

        bytes memory signature1;
        bytes memory signature2;
        bytes memory signature3;
        {
            bytes32 digestHash = signatureUtils.calculateQueueWithdrawalDigestHash(
                staker,
                strategiesToWithdraw1,
                sharesToWithdraw1,
                0, // stakerNonce
                expiry,
                address(IDelegationManager(address(0x1))),
                block.chainid
            );

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash);
            signature1 = abi.encodePacked(r, s, v);
            signature2 = abi.encodePacked(r, s, v);
            signature3 = abi.encodePacked(r, s, v);
        }

        IDelegationManager.QueuedWithdrawalWithSignatureParams memory queuedWithdrawalWithSig1;
        IDelegationManager.QueuedWithdrawalWithSignatureParams memory queuedWithdrawalWithSig2;
        IDelegationManager.QueuedWithdrawalWithSignatureParams memory queuedWithdrawalWithSig3;

        queuedWithdrawalWithSig1 = IDelegationManager.QueuedWithdrawalWithSignatureParams({
            strategies: strategiesToWithdraw1,
            shares: sharesToWithdraw1,
            withdrawer: address(receiverContract),
            staker: staker,
            signature: signature1,
            expiry: expiry
        });
        queuedWithdrawalWithSig2 = queuedWithdrawalWithSig1;
        queuedWithdrawalWithSig3 = queuedWithdrawalWithSig1;

        IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalWithSigParams;
        // aray with 3 elements
        queuedWithdrawalWithSigParams = new IDelegationManager.QueuedWithdrawalWithSignatureParams[](3);
        queuedWithdrawalWithSigParams[0] = queuedWithdrawalWithSig1;
        queuedWithdrawalWithSigParams[1] = queuedWithdrawalWithSig2;
        queuedWithdrawalWithSigParams[2] = queuedWithdrawalWithSig3;

        bytes memory message = abi.encode(string(
            EigenlayerMsgEncoders.encodeQueueWithdrawalsWithSignatureMsg(
                queuedWithdrawalWithSigParams
            )
        )); // CCIP turns the message into string when sending

        IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory dwp =
            restakingConnector.decodeQueueWithdrawalsWithSignatureMessage(message);

        require(dwp[0].staker == deployer, "wrong _staker[0]");
        require(dwp[1].staker == deployer, "wrong _staker[1]");
        require(dwp[2].staker == deployer, "wrong _staker[2]");

        require(dwp[0].withdrawer == address(receiverContract), "wrong _withdrawer[0]");
        require(dwp[1].withdrawer == address(receiverContract), "wrong _withdrawer[1]");
        require(dwp[2].withdrawer == address(receiverContract), "wrong _withdrawer[2]");

        require(address(dwp[0].strategies[0]) == address(strategy), "wrong _strategy[0]");
        require(address(dwp[1].strategies[0]) == address(strategy), "wrong _strategy[1]");
        require(address(dwp[2].strategies[0]) == address(strategy), "wrong _strategy[2]");

        console.log(dwp[1].shares[0]);
        console.log(dwp[2].shares[0]);
        require(dwp[0].shares[0] == amount, "wrong _sharesToWithdraw[0]");
        require(dwp[1].shares[0] == amount, "wrong _sharesToWithdraw[1]");
        require(dwp[2].shares[0] == amount, "wrong _sharesToWithdraw[2]");

        require(keccak256(dwp[0].signature) == keccak256(signature1), "wrong _signature[0]");
        require(keccak256(dwp[1].signature) == keccak256(signature2), "wrong _signature[1]");
        require(keccak256(dwp[2].signature) == keccak256(signature3), "wrong _signature[2]");

        // console.log("staker");
        // console.log(dwp[0].staker);
        // console.log("withdrawer");
        // console.log(dwp[0].withdrawer);
        // console.log("strategy");
        // console.log(address(dwp[0].strategies[0]));
        // console.log("sharesToWithdraw");
        // console.log(dwp[0].shares[0]);
        // console.log("sigature");
        // console.logBytes(dwp[0].signature);
    }

    function test_Decode_RevertBadSignature_QueueWithdrawalsWithSignature() public {

        IStrategy[] memory strategiesToWithdraw1 = new IStrategy[](1);
        strategiesToWithdraw1[0] = strategy;

        uint256[] memory sharesToWithdraw1 = new uint256[](1);
        sharesToWithdraw1[0] = amount;

        bytes memory signature1 = new bytes(0); // bad signature length, hsould be 65 bytes

        IDelegationManager.QueuedWithdrawalWithSignatureParams memory queuedWithdrawalWithSig1;
        queuedWithdrawalWithSig1 = IDelegationManager.QueuedWithdrawalWithSignatureParams({
            strategies: strategiesToWithdraw1,
            shares: sharesToWithdraw1,
            withdrawer: address(receiverContract),
            staker: staker,
            signature: signature1,
            expiry: expiry
        });

        IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalWithSigParams;
        // aray with 3 elements
        queuedWithdrawalWithSigParams = new IDelegationManager.QueuedWithdrawalWithSignatureParams[](1);
        queuedWithdrawalWithSigParams[0] = queuedWithdrawalWithSig1;

        bytes memory message = abi.encode(string(
            EigenlayerMsgEncoders.encodeQueueWithdrawalsWithSignatureMsg(
                queuedWithdrawalWithSigParams
            )
        )); // CCIP turns the message into string when sending

        vm.expectRevert("decodeQueueWithdrawalsWithSignatureMessage: invalid signature length");
        restakingConnector.decodeQueueWithdrawalsWithSignatureMessage(message);
    }

    /*
     *
     *
     *                   Complete Withdrawals
     *
     *
    */

    function test_Decode_CompleteQueuedWithdrawal() public {

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);

        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = 0.00321 ether;

        address _staker = deployer;

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: _staker,
            delegatedTo: address(0x0),
            withdrawer: address(receiverContract),
            nonce: 0,
            startBlock: uint32(block.number),
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
        });

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = token;
        uint256 middlewareTimesIndex = 0; // not used, used when slashing is enabled;
        bool receiveAsTokens = true;

        bytes memory message_bytes = EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
            withdrawal,
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );
        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));
        console.logBytes(message);

        (
            IDelegationManager.Withdrawal memory _withdrawal,
            IERC20[] memory _tokensToWithdraw,
            uint256 _middlewareTimesIndex,
            bool _receiveAsTokens
        ) = restakingConnector.decodeCompleteWithdrawalMessage(message);

        require(_withdrawal.shares[0] == withdrawal.shares[0], "decodeCompleteWithdrawalMessage shares error");
        require(_withdrawal.staker == withdrawal.staker, "decodeCompleteWithdrawalMessage staker error");
        require(_withdrawal.withdrawer == withdrawal.withdrawer, "decodeCompleteWithdrawalMessage withdrawer error");
        require(address(_tokensToWithdraw[0]) == address(tokensToWithdraw[0]), "decodeCompleteWithdrawalMessage tokensToWithdraw error");
        require(_receiveAsTokens == receiveAsTokens, "decodeCompleteWithdrawalMessage error");
    }

    /// Note: Need to do a array version of this
    function test_Decode_Array_CompleteQueuedWithdrawal() public {

    }

    function test_Decode_TransferToStakerMessage() public {

        bytes32 withdrawalRoot1 = 0x8c20d3a37feccd4dcb9fa5fbd299b37db00fde77cbb7540e2850999fc7d8ec77;

        TransferToStakerMessage memory tts_msg = restakingConnector.decodeTransferToStakerMessage(
            abi.encode(string(
                EigenlayerMsgEncoders.encodeTransferToStakerMsg(
                    withdrawalRoot1
                )
            ))
        );

        require(tts_msg.withdrawalRoot == withdrawalRoot1, "incorrect withdrawalRoot");
    }

    /*
     *
     *
     *                   Delegation
     *
     *
    */

    function test_Decode_DelegateToBySignature_BothSigned() public {

        address staker = vm.addr(0x1);
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
                staker,
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
            staker,
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
        ) = restakingConnector.decodeDelegateToBySignature(message);

        require(staker == _staker, "staker incorrect");
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

    function test_Decode_DelegateToBySignature_Unsigned() public {

        address staker = vm.addr(0x1);
        address operator = vm.addr(0x2);
        address delegationManager = vm.addr(0xde);

        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry;
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;

        bytes memory signature1;
        bytes memory signature2;

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
            staker,
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
        ) = restakingConnector.decodeDelegateToBySignature(message);

        require(staker == _staker, "staker incorrect");
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

    function test_Decode_DelegateToBySignature_StakerSigned() public {

        address staker = vm.addr(0x1);
        address operator = vm.addr(0x2);
        address delegationManager = vm.addr(0xde);

        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry;
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;

        bytes memory signature1;
        bytes memory signature2;
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
            staker,
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
        ) = restakingConnector.decodeDelegateToBySignature(message);

        require(staker == _staker, "staker incorrect");
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

    function test_Decode_DelegateToBySignature_ApproverSigned() public {

        address staker = vm.addr(0x1);
        address operator = vm.addr(0x2);
        address delegationManager = vm.addr(0xde);

        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry;
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;

        bytes memory signature1;
        bytes memory signature2;
        {
            uint256 sig1_expiry = 6;

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
            staker,
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
        ) = restakingConnector.decodeDelegateToBySignature(message);

        require(staker == _staker, "staker incorrect");
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

    function test_Decode_Undelegate() public {

        address staker = vm.addr(0x1);

        address _staker = restakingConnector.decodeUndelegate(
            abi.encode(string(
                EigenlayerMsgEncoders.encodeUndelegateMsg(staker)
            ))
        );

        require(staker == _staker, "staker incorrect");
    }
}
