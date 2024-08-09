// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {EigenlayerDepositParams, EigenlayerDepositMessage} from "../src/interfaces/IRestakingConnector.sol";
import {EIP1271SignatureUtils} from "eigenlayer-contracts/src/contracts/libraries/EIP1271SignatureUtils.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {FunctionSelectorDecoder} from "../src/FunctionSelectorDecoder.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";


contract MessagePassingTest is Test {

    uint256 public deployerKey;
    address public deployer;

    EigenlayerMsgEncoders public eigenlayerMsgEncoders;
    FunctionSelectorDecoder public functionSelectorDecoder;

    function setUp() public {
		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        eigenlayerMsgEncoders = new EigenlayerMsgEncoders();
        functionSelectorDecoder = new FunctionSelectorDecoder();
    }

    function test_DecodeFunctionSelectors() public {

        bytes memory message1 = hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000044f7e784ef00000000000000000000000000000000000000000000000000000000000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c00000000000000000000000000000000000000000000000000000000";
        bytes4 functionSelector1 = functionSelectorDecoder.decodeFunctionSelector(message1);
        require(functionSelector1 == 0xf7e784ef, "wrong functionSelector");

        bytes memory message2 = abi.encode(string(abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")),
            86421,
            0xBd4bcb3AD20E9d85D5152aE68F45f40aF8952159,
            0x3Eef6ec7a9679e60CC57D9688E9eC0e6624D687A,
            0.0077 ether,
            0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c,
            hex"3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c"
        )));
        bytes4 functionSelector2 = functionSelectorDecoder.decodeFunctionSelector(message2);
        require(functionSelector2 == 0x32e89ace, "wrong functionSelector");
    }

    function test_DecodeEigenlayerMsg_Deposit() public pure {

        // 0000000000000000000000000000000000000000000000000000000000000020
        // 0000000000000000000000000000000000000000000000000000000000000044
        // f7e784ef00000000000000000000000000000000000000000000000000000000
        // 000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a
        // 1b7b6c2c00000000000000000000000000000000000000000000000000000000
        bytes memory message = hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000044f7e784ef00000000000000000000000000000000000000000000000000000000000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c00000000000000000000000000000000000000000000000000000000";

        bytes32 offset;
        bytes32 length;
        bytes4 functionSelector;
        uint256 amount;
        address staker;

        assembly {
            offset := mload(add(message, 32))
            length := mload(add(message, 64))
            functionSelector := mload(add(message, 96))
            amount := mload(add(message, 100))
            staker := mload(add(message, 132))
        }

        bytes4 functionSelector2 = bytes4(keccak256("depositIntoStrategy(uint256,address)"));

        require(functionSelector == functionSelector2, "functionSelectors do not match");

        EigenlayerDepositMessage memory emsg = EigenlayerDepositMessage({
            functionSelector: functionSelector,
            amount: amount,
            staker: staker
        });

        require(emsg.functionSelector == bytes4(0xf7e784ef), "decoded incorrect EigenlayerDepositMessage.functionSelector");
        require(emsg.amount == 2, "decoded incorrect EigenlayerDepositMessage.amount");
        require(emsg.staker == 0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c, "decoded incorrect EigenlayerDepositMessage.staker");
    }

    function test_encodesDepositWithSignatureCorrectly() public {

        address strategy = 0xBd4bcb3AD20E9d85D5152aE68F45f40aF8952159;
        address token = 0x3Eef6ec7a9679e60CC57D9688E9eC0e6624D687A;
        uint256 amount = 0.0077 ether;
        address staker = 0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c;
        uint256 expiry = 86421;
        bytes memory signature = hex"3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c";

        bytes memory messageBytes = abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")),
            strategy,
            token,
            amount,
            staker,
            expiry,
            signature
        );
        bytes memory messageBytes2 = eigenlayerMsgEncoders.encodeDepositIntoStrategyWithSignatureMsg(
            strategy,
            token,
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

    function test_DecodeEigenlayerMsg_DepositWithSignature() public {

        // function depositIntoStrategyWithSignature(
        //     IStrategy strategy,
        //     IERC20 token,
        //     uint256 amount,
        //     address staker,
        //     uint256 expiry,
        //     bytes memory signature
        // ) external onlyWhenNotPaused(PAUSED_DEPOSITS) nonReentrant returns (uint256 shares)

        // encode message payload
        bytes memory message_bytes = eigenlayerMsgEncoders.encodeDepositIntoStrategyWithSignatureMsg(
            0xBd4bcb3AD20E9d85D5152aE68F45f40aF8952159,
            0x3Eef6ec7a9679e60CC57D9688E9eC0e6624D687A,
            0.0077 ether,
            0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c,
            86421,
            hex"3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c"
        );
        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));

        ////////////////////////////////////////////////////////
        //// Message payload offsets for assembly decoding
        ////////////////////////////////////////////////////////

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000144 [64]
        // 32e89ace000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40a [96] bytes4 truncates the right
        // f8952159        [100] reads 32 bytes from offset [100] right-to-left up to the function selector
        // 0000000000000000000000003eef6ec7a9679e60cc57d9688e9ec0e6624d687a [132]
        // 000000000000000000000000000000000000000000000000001b5b1bf4c54000 [164] uint256 amount in hex
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [196]
        // 0000000000000000000000000000000000000000000000000000000000015195 [228] expiry
        // 00000000000000000000000000000000000000000000000000000000000000c0 [260] offset: 192 bytes
        // 0000000000000000000000000000000000000000000000000000000000000041 [292] length: 65 bytes
        // 3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee [324] signature: r
        // 3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d5 [356] signature: s
        // 1c00000000000000000000000000000000000000000000000000000000000000 [388] signature: v (uint8 = bytes1)
        // 00000000000000000000000000000000000000000000000000000000

        bytes32 offset;
        bytes32 length;

        bytes4 functionSelector;
        address strategy;
        address token;
        uint256 amount;
        address staker;
        uint256 expiry;

        bytes32 sig_offset;
        bytes32 sig_length;
        bytes32 r;
        bytes32 s;
        bytes1 v;

        assembly {
            offset := mload(add(message, 32))
            length := mload(add(message, 64))

            functionSelector := mload(add(message, 96))
            strategy := mload(add(message, 100))
            token := mload(add(message, 132))
            amount := mload(add(message, 164))
            staker := mload(add(message, 196))
            expiry := mload(add(message, 228))

            sig_offset := mload(add(message, 260))
            sig_length := mload(add(message, 292))

            r := mload(add(message, 324))
            s := mload(add(message, 356))
            v := mload(add(message, 388))
        }

        // console.log("functionSelector:");
        // console.logBytes4(functionSelector);

        // console.log("expiry:");
        // console.log(expiry);

        // console.log("strategy:");
        // console.log(strategy);

        // console.log("token:");
        // console.log(token);

        // console.log("amount:");
        // console.log(amount);

        // console.log("staker:");
        // console.log(staker);

        bytes memory signature = abi.encodePacked(r,s,v);
        // console.log("signature:");
        // console.logBytes(signature);

        require(signature.length == 65, "invalid signature length");
        bytes4 functionSelector2 = bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)"));
        require(functionSelector == functionSelector2, "functionSelectors do not match");
        require(functionSelector == 0x32e89ace, "functionSelectors do not match");
    }

    function test_DecodeEigenlayerMsg_QueueWithdrawal() public {

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);
        IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal;

        IStrategy strategy = IStrategy(0xBd4bcb3AD20E9d85D5152aE68F45f40aF8952159);
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

        bytes memory message_bytes = eigenlayerMsgEncoders.encodeQueueWithdrawalMsg(
            queuedWithdrawalParams
        );

        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));

        ////////////////////////////////////////////////////////
        //// Message payload offsets for assembly decoding
        ////////////////////////////////////////////////////////

        // functionSelector signature:
        // bytes4(keccak256("queueWithdrawals((address[],uint256[],address)[])")),

        // Params:
        // queuedWithdrawal = IDelegationManager.QueuedWithdrawalParams({
        //     strategies: strategiesToWithdraw,
        //     shares: sharesToWithdraw,
        //     withdrawer: withdrawer
        // });

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

        console.log("functionSelector");
        console.logBytes4(functionSelector);

        console.log("withdrawer");
        console.log(_withdrawer);

        console.log("strategy");
        console.log(_strategy);

        console.log("sharesToWithdraw");
        console.log(_sharesToWithdraw);

        require(_withdrawer == queuedWithdrawalParams[0].withdrawer, "decoded withdrawer incorrect");
        require(_sharesToWithdraw == queuedWithdrawalParams[0].shares[0], "decoded shares incorrect");
        require(_strategy == address(queuedWithdrawalParams[0].strategies[0]), "decoded strategy incorrect");
    }

    function test_DecodeEigenlayerMsg_MultipleQueueWithdrawals() public {

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

        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams;
        queuedWithdrawalParams = new IDelegationManager.QueuedWithdrawalParams[](3);

        queuedWithdrawalParams[0] = queuedWithdrawal1;
        queuedWithdrawalParams[1] = queuedWithdrawal2;
        queuedWithdrawalParams[2] = queuedWithdrawal3;

        bytes memory message_bytes = eigenlayerMsgEncoders.encodeQueueWithdrawalMsg(
            queuedWithdrawalParams
        );

        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));
        console.log("message:");
        console.logBytes(message);

        RestakingConnector restakingConnector = new RestakingConnector();

        IDelegationManager.QueuedWithdrawalParams[] memory decodedQueuedWithdrawals;
        decodedQueuedWithdrawals = restakingConnector.decodeQueueWithdrawalsArrayMessage(message);

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


    // function test_DecodeEigenlayerMsg_CompleteQueuedWithdrawal() public {

    //     IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
    //     uint256[] memory sharesToWithdraw = new uint256[](1);

    //     IStrategy strategy = IStrategy(0xBd4bcb3AD20E9d85D5152aE68F45f40aF8952159);
    //     strategiesToWithdraw[0] = strategy;
    //     sharesToWithdraw[0] = 0.00321;

    //     // IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal()[1];
    //     // withdrawals[0] = IDelegationManager.Withdrawal({
    //     IDelegationManager.Withdrawal memory withdrawal;
    //     withdrawal = IDelegationManager.Withdrawal({
    //         staker: deployer, // msg.sender
    //         delegatedTo: address(0), // not delegated to anyone
    //         withdrawer: deployer,
    //         nonce: 0,
    //         startBlock: uint32(1),
    //         strategies: strategiesToWithdraw,
    //         shares: sharesToWithdraw
    //     });

    //     IERC20[] memory tokensToWithdraw = new IERC20[](1);
    //     tokensToWithdraw[0] = strategy.underlyingToken();
    //     uint256 middlewareTimesIndex = 0; // not used, used when slashing is enabled;
    //     bool receiveAsTokens = true;

    //     uint256 newTimestamp = block.timestamp + 60; // 60 seconds = 5 blocks (12second per block)
    //     vm.warp(newTimestamp);
    //     vm.roll(newTimestamp / 12);
    //     console.log("block.timestamp :", block.timestamp);
    //     console.log("block.number :", block.number);

    //     uint256 delay = delegationManager.getWithdrawalDelay(strategiesToWithdraw);
    //     console.log("withdrawal delay (blocks)", delay); // 4 blocks withdrawal delay

    //     delegationManager.completeQueuedWithdrawal(
    //         withdrawal,
    //         tokensToWithdraw,
    //         middlewareTimesIndex,
    //         receiveAsTokens
    //     );

    // }
}
