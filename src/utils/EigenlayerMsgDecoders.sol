//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {console} from "forge-std/Test.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// Deposit
import {
    EigenlayerDepositMessage,
    EigenlayerDepositParams
} from "../interfaces/IRestakingConnector.sol";
// DepositWithSignature
import {
    EigenlayerDepositWithSignatureMessage,
    EigenlayerDepositWithSignatureParams
} from "../interfaces/IRestakingConnector.sol";
// QueueWithdrawals
import {EigenlayerQueueWithdrawalsParams} from "../interfaces/IRestakingConnector.sol";
import {IEigenlayerMsgDecoders} from "../interfaces/IEigenlayerMsgDecoders.sol";


contract EigenlayerMsgDecoders is IEigenlayerMsgDecoders {

    function decodeDepositMessage(
        bytes memory message
    ) public returns (EigenlayerDepositMessage memory) {

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

        EigenlayerDepositMessage memory eigenlayerDepositMessage = EigenlayerDepositMessage({
            functionSelector: functionSelector,
            amount: amount,
            staker: staker
        });

        emit EigenlayerDepositParams(functionSelector, amount, staker);

        return eigenlayerDepositMessage;
    }

    function decodeDepositWithSignatureMessage(
        bytes memory message
    ) public returns (EigenlayerDepositWithSignatureMessage memory) {
        ////////////////////////////////////////////////////////
        //// Message payload offsets for assembly destructuring
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
        // 3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee [324] signature r
        // 3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d5 [356] signature s
        // 1c00000000000000000000000000000000000000000000000000000000000000 [388] v: uint8 = bytes1
        // 00000000000000000000000000000000000000000000000000000000

        bytes32 offset;
        bytes32 length;

        bytes4 functionSelector;
        address _strategy;
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
            _strategy := mload(add(message, 100))
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

        bytes memory signature = abi.encodePacked(r,s,v);

        require(signature.length == 65, "invalid signature length");

        EigenlayerDepositWithSignatureMessage memory eigenlayerDepositWithSignatureMessage;
        eigenlayerDepositWithSignatureMessage = EigenlayerDepositWithSignatureMessage({
            expiry: expiry,
            strategy: _strategy,
            token: token,
            amount: amount,
            staker: staker,
            signature: signature
        });

        emit EigenlayerDepositWithSignatureParams(functionSelector, amount, staker);

        return eigenlayerDepositWithSignatureMessage;
    }


    function decodeQueueWithdrawalsMessage(
        bytes memory message
    ) public returns (IDelegationManager.QueuedWithdrawalParams[] memory) {

        /// @dev note: Need to account for bytes message including arrays of QueuedWithdrawalParams
        /// We will need to check array length in SenderCCIP to determine gas as well.

        uint256 arrayLength;

        assembly {
            arrayLength := mload(add(message, 132))
        }

        IDelegationManager.QueuedWithdrawalParams[] memory arrayQueuedWithdrawalParams =
            new IDelegationManager.QueuedWithdrawalParams[](arrayLength);

        for (uint256 i; i < arrayLength; i++) {
            IDelegationManager.QueuedWithdrawalParams memory wp;
            wp = decodeSingleQueueWithdrawalMessage(message, arrayLength, i);
            // console.log("wp.shares:", wp.shares[0]);
            // console.log("wp.withdrawer:", wp.withdrawer);
            arrayQueuedWithdrawalParams[i] = wp;
        }

        return arrayQueuedWithdrawalParams;
    }


    function decodeSingleQueueWithdrawalMessage(
        bytes memory message,
        uint256 arrayLength,
        uint256 i
    ) internal returns (IDelegationManager.QueuedWithdrawalParams memory) {
        /// @dev: expect to use this in a for-loop with i iteration variable

        //////////////////////////////////////////////////
        //// Deserializing messages: offsets for assembly
        //////////////////////////////////////////////////
        //
        // functionSelector signature:
        // bytes4(keccak256("queueWithdrawals((address[],uint256[],address)[])")),
        //
        // Params:
        // queuedWithdrawal = IDelegationManager.QueuedWithdrawalParams({
        //     strategies: strategiesToWithdraw,
        //     shares: sharesToWithdraw,
        //     withdrawer: withdrawer
        // });

        ////////////////////////////////////////////////////////////////////////
        //// An example with 1 element in QueuedWithdrawalParams[]
        ////////////////////////////////////////////////////////////////////////
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

        ////////////////////////////////////////////////////////////////////////
        //// An example with 2 elements in QueuedWithdrawalParams[]
        ////////////////////////////////////////////////////////////////////////
        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 0000000000000000000000000000000000000000000000000000000000000244 [64] string length
        // 0dd8dd02                                                         [96] function selector
        // 0000000000000000000000000000000000000000000000000000000000000020 [100] array offset
        // 0000000000000000000000000000000000000000000000000000000000000002 [132] array length
        // 0000000000000000000000000000000000000000000000000000000000000040 [164] struct1 offset (2 lines down)
        // 0000000000000000000000000000000000000000000000000000000000000120 [196] struct2 offset (9 lines down)
        // 0000000000000000000000000000000000000000000000000000000000000060 [228] struct1_field1 offset
        // 00000000000000000000000000000000000000000000000000000000000000a0 [260] struct1_field2 offset
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [292] struct1_field3 (static var)
        // 0000000000000000000000000000000000000000000000000000000000000001 [324] struct1_field1 length
        // 000000000000000000000000b222222ad20e9d85d5152ae68f45f40a22222222 [356] struct1_field1 value
        // 0000000000000000000000000000000000000000000000000000000000000001 [388] struct1_field2 length
        // 0000000000000000000000000000000000000000000000000003f18a03b36000 [420] struct1_field2 value
        // 0000000000000000000000000000000000000000000000000000000000000060 [452] struct2_field1 offset
        // 00000000000000000000000000000000000000000000000000000000000000a0 [484] struct2_field2 offset
        // 0000000000000000000000002b5ad5c4795c026514f8317c7a215e218dccd6cf [516] struct2_field3 (static var)
        // 0000000000000000000000000000000000000000000000000000000000000001 [548] struct2_field1 length
        // 000000000000000000000000b999999ad20e9d85d5152ae68f45f40a99999999 [580] struct2_field1 value
        // 0000000000000000000000000000000000000000000000000000000000000001 [612] struct2_field2 length
        // 000000000000000000000000000000000000000000000000000c38a96a070000 [644] struct2_field2 value
        // 00000000000000000000000000000000000000000000000000000000


        // bytes32 _strOffset;
        // bytes32 _strLength;
        bytes4 functionSelector;
        // bytes32 _arrayOffset;
        // bytes32 _arrayLength;
        // bytes32 _structOffset;
        // bytes32 _structField1Offset;
        // bytes32 _structField2Offset;
        address _withdrawer;
        // bytes32 _structField1ArrayLength;
        address _strategy;
        // bytes32 _structField2ArrayLength;
        uint256 _sharesToWithdraw;

        /// @dev note: Need to account for arrays of QueuedWithdrawalParams.
        /// - determine length of QueuedWithdrawalParam[] from bytes message
        /// - loop through and deserialise each element in QueuedWithdrawalParams[]
        /// with the correct offsets
        require(arrayLength >= 1, "array cannot be zero length");

        uint256 offset = (arrayLength - 1) + (7 * i);
        // Every extra element in the QueueWithdrawalParams[] array adds
        // one extra struct offset 32byte word (1 line), so shift everything down by (arrayLength - 1).
        //
        // Each QueueWithdrawalParams takes 7 lines, so when reading the ith element,
        // increase offset by 7 * i:
        //      1 element:  offset = (1 - 1) + (7 * 0) = 0
        //      2 elements: offset = (2 - 1) + (7 * 1) = 8
        //      3 elements: offset = (3 - 1) + (7 * 2) = 16

        uint256 withdrawerOffset = 260 + offset * 32;
        uint256 strategyOffset = 324 + offset * 32;
        uint256 sharesToWithdrawOffset = 388 + offset * 32;

        assembly {
            // _strOffset := mload(add(message, 32))
            // _strLength := mload(add(message, 64))
            functionSelector := mload(add(message, 96))
            // _arrayOffset := mload(add(message, 100))
            // _arrayLength := mload(add(message, 132))
            // _structOffset := mload(add(message, 164))
            // _structField1Offset := mload(add(message, 196))
            // _structField2Offset := mload(add(message, 228))
            _withdrawer := mload(add(message, withdrawerOffset))
            // _structField1ArrayLength := mload(add(message, 292))
            _strategy := mload(add(message, strategyOffset))
            // _structField2ArrayLength := mload(add(message, 356))
            _sharesToWithdraw := mload(add(message, sharesToWithdrawOffset))
        }

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);

        strategiesToWithdraw[0] = IStrategy(_strategy);
        sharesToWithdraw[0] = _sharesToWithdraw;

        IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawalParams;
        queuedWithdrawalParams = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw,
            withdrawer: _withdrawer
        });

        emit EigenlayerQueueWithdrawalsParams(functionSelector, _sharesToWithdraw, _withdrawer);

        return queuedWithdrawalParams;
    }

    function decodeQueueWithdrawalsWithSignatureMessage(
        bytes memory message
    ) public returns (
        IDelegationManager.QueuedWithdrawalParams[] memory
    ) {

        /// @dev note: Need to account for bytes message including arrays of QueuedWithdrawalParams
        /// We will need to check array length in SenderCCIP to determine gas as well.

        uint256 arrayLength;

        assembly {
            arrayLength := mload(add(message, 132))
        }

        IDelegationManager.QueuedWithdrawalParams[] memory arrayQueuedWithdrawalParams =
            new IDelegationManager.QueuedWithdrawalParams[](arrayLength);

        for (uint256 i; i < arrayLength; i++) {
            IDelegationManager.QueuedWithdrawalParams memory wp;
            wp = decodeSingleQueueWithdrawalMessage(message, arrayLength, i);
            // console.log("wp.shares:", wp.shares[0]);
            // console.log("wp.withdrawer:", wp.withdrawer);
            arrayQueuedWithdrawalParams[i] = wp;
        }

        return arrayQueuedWithdrawalParams;
    }

    function decodeSingleQueueWithdrawalWithSignatureMessage(
        bytes memory message,
        uint256 arrayLength,
        uint256 i
    ) internal returns (IDelegationManager.QueuedWithdrawalParams memory) {
        /// @dev: expect to use this in a for-loop with i iteration variable

        //////////////////////////////////////////////////
        //// Deserializing messages: offsets for assembly
        //////////////////////////////////////////////////
        //
        // functionSelector signature:
        // bytes4(keccak256("queueWithdrawals((address[],uint256[],address)[])")),
        //
        // Params:
        // queuedWithdrawal = IDelegationManager.QueuedWithdrawalParams({
        //     strategies: strategiesToWithdraw,
        //     shares: sharesToWithdraw,
        //     withdrawer: withdrawer
        // });

        ////////////////////////////////////////////////////////////////////////
        //// An example with 1 element in QueuedWithdrawalParams[]
        ////////////////////////////////////////////////////////////////////////
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

        ////////////////////////////////////////////////////////////////////////
        //// An example with 2 elements in QueuedWithdrawalParams[]
        ////////////////////////////////////////////////////////////////////////
        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 0000000000000000000000000000000000000000000000000000000000000244 [64] string length
        // 0dd8dd02                                                         [96] function selector
        // 0000000000000000000000000000000000000000000000000000000000000020 [100] array offset
        // 0000000000000000000000000000000000000000000000000000000000000002 [132] array length
        // 0000000000000000000000000000000000000000000000000000000000000040 [164] struct1 offset (2 lines down)
        // 0000000000000000000000000000000000000000000000000000000000000120 [196] struct2 offset (9 lines down)
        // 0000000000000000000000000000000000000000000000000000000000000060 [228] struct1_field1 offset
        // 00000000000000000000000000000000000000000000000000000000000000a0 [260] struct1_field2 offset
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [292] struct1_field3 (static var)
        // 0000000000000000000000000000000000000000000000000000000000000001 [324] struct1_field1 length
        // 000000000000000000000000b222222ad20e9d85d5152ae68f45f40a22222222 [356] struct1_field1 value
        // 0000000000000000000000000000000000000000000000000000000000000001 [388] struct1_field2 length
        // 0000000000000000000000000000000000000000000000000003f18a03b36000 [420] struct1_field2 value
        // 0000000000000000000000000000000000000000000000000000000000000060 [452] struct2_field1 offset
        // 00000000000000000000000000000000000000000000000000000000000000a0 [484] struct2_field2 offset
        // 0000000000000000000000002b5ad5c4795c026514f8317c7a215e218dccd6cf [516] struct2_field3 (static var)
        // 0000000000000000000000000000000000000000000000000000000000000001 [548] struct2_field1 length
        // 000000000000000000000000b999999ad20e9d85d5152ae68f45f40a99999999 [580] struct2_field1 value
        // 0000000000000000000000000000000000000000000000000000000000000001 [612] struct2_field2 length
        // 000000000000000000000000000000000000000000000000000c38a96a070000 [644] struct2_field2 value
        // 00000000000000000000000000000000000000000000000000000000


        // bytes32 _strOffset;
        // bytes32 _strLength;
        bytes4 functionSelector;
        // bytes32 _arrayOffset;
        // bytes32 _arrayLength;
        // bytes32 _structOffset;
        // bytes32 _structField1Offset;
        // bytes32 _structField2Offset;
        address _withdrawer;
        // bytes32 _structField1ArrayLength;
        address _strategy;
        // bytes32 _structField2ArrayLength;
        uint256 _sharesToWithdraw;

        /// @dev note: Need to account for arrays of QueuedWithdrawalParams.
        /// - determine length of QueuedWithdrawalParam[] from bytes message
        /// - loop through and deserialise each element in QueuedWithdrawalParams[]
        /// with the correct offsets
        require(arrayLength >= 1, "array cannot be zero length");

        uint256 offset = (arrayLength - 1) + (7 * i);
        // Every extra element in the QueueWithdrawalParams[] array adds
        // one extra struct offset 32byte word (1 line), so shift everything down by (arrayLength - 1).
        //
        // Each QueueWithdrawalParams takes 7 lines, so when reading the ith element,
        // increase offset by 7 * i:
        //      1 element:  offset = (1 - 1) + (7 * 0) = 0
        //      2 elements: offset = (2 - 1) + (7 * 1) = 8
        //      3 elements: offset = (3 - 1) + (7 * 2) = 16

        uint256 withdrawerOffset = 260 + offset * 32;
        uint256 strategyOffset = 324 + offset * 32;
        uint256 sharesToWithdrawOffset = 388 + offset * 32;

        assembly {
            // _strOffset := mload(add(message, 32))
            // _strLength := mload(add(message, 64))
            functionSelector := mload(add(message, 96))
            // _arrayOffset := mload(add(message, 100))
            // _arrayLength := mload(add(message, 132))
            // _structOffset := mload(add(message, 164))
            // _structField1Offset := mload(add(message, 196))
            // _structField2Offset := mload(add(message, 228))
            _withdrawer := mload(add(message, withdrawerOffset))
            // _structField1ArrayLength := mload(add(message, 292))
            _strategy := mload(add(message, strategyOffset))
            // _structField2ArrayLength := mload(add(message, 356))
            _sharesToWithdraw := mload(add(message, sharesToWithdrawOffset))
        }

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);

        strategiesToWithdraw[0] = IStrategy(_strategy);
        sharesToWithdraw[0] = _sharesToWithdraw;

        IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawalParams;
        queuedWithdrawalParams = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw,
            withdrawer: _withdrawer
        });

        emit EigenlayerQueueWithdrawalsParams(functionSelector, _sharesToWithdraw, _withdrawer);

        return queuedWithdrawalParams;
    }


    function decodeCompleteWithdrawalMessage(bytes memory message) public returns (
        IDelegationManager.Withdrawal memory,
        IERC20[] memory,
        uint256,
        bool
    ) {

        IDelegationManager.Withdrawal memory _withdrawal = _decodeCompleteWithdrawalMessagePart1(message);
        (
            IERC20[] memory _tokensToWithdraw,
            uint256 _middlewareTimesIndex,
            bool _receiveAsTokens
        ) = _decodeCompleteWithdrawalMessagePart2(message);

        return (
            _withdrawal,
            _tokensToWithdraw,
            _middlewareTimesIndex,
            _receiveAsTokens
        );
    }

    function _decodeCompleteWithdrawalMessagePart1(bytes memory message) internal returns (
        IDelegationManager.Withdrawal memory
    ) {
        /// @note decodes the first half of the CompleteWithdrawalMessage as we run into
        /// a "stack to deep" error with more than 16 variables in the function.

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000224 [64]
        // 54b2bf29                                                         [96]
        // 0000000000000000000000000000000000000000000000000000000000000080 [100] withdrawal struct offset (129 bytes = 4 lines)
        // 00000000000000000000000000000000000000000000000000000000000001e0 [132] tokens array offset (420 bytes = 15 lines)
        // 0000000000000000000000000000000000000000000000000000000000000000 [164] middlewareTimesIndex (static var)
        // 0000000000000000000000000000000000000000000000000000000000000001 [196] receiveAsTokens (static var)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [228] struct_field_1: staker
        // 0000000000000000000000000000000000000000000000000000000000000000 [260] struct_field_2: delegatedTo
        // 0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf [292] struct_field_3: withdrawer
        // 0000000000000000000000000000000000000000000000000000000000000000 [324] struct_field_4: nonce
        // 0000000000000000000000000000000000000000000000000000000000000001 [356] struct_field_5: startBlock
        // 00000000000000000000000000000000000000000000000000000000000000e0 [388] struct_field_6: strategies[] offset (224 bytes = 7 lines)
        // 0000000000000000000000000000000000000000000000000000000000000120 [420] struct_field_7: shares[] offset (288 bytes = 9 lines)
        // 0000000000000000000000000000000000000000000000000000000000000001 [452] strategies[] length
        // 000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40af8952159 [484] strategies[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [516] shares[] length
        // 000000000000000000000000000000000000000000000000000b677a5dbaa000 [548] shares[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [580] tokens array length
        // 0000000000000000000000003eef6ec7a9679e60cc57d9688e9ec0e6624d687a [612] tokens[0] value
        // 00000000000000000000000000000000000000000000000000000000

        // struct Withdrawal {
        //     address staker;
        //     address delegatedTo;
        //     address withdrawer;
        //     uint256 nonce;
        //     uint32 startBlock;
        //     IStrategy[] strategies;
        //     uint256[] shares;
        // }

        // bytes32 _str_offset;
        // bytes32 _str_length;
        // bytes4 functionSelector;
        // uint256 withdrawalStructOffset;
        // uint256 tokensArrayOffset;
        // uint256 middlewareTimesIndex;
        // bool receiveAsTokens;

        address staker;
        address delegatedTo;
        address withdrawer;
        uint256 nonce;
        uint32 startBlock;

        // uint256 strategies_offset;
        // uint256 shares_offset;
        uint256 strategies_length;
        uint256 shares_length;
        IStrategy strategy0;
        uint256 share0;
        // uint256 tokensArrayLength;
        // address tokensToWithdraw0;

        assembly {
            // _str_offset := mload(add(message, 32))
            // _str_length := mload(add(message, 64))
            // functionSelector := mload(add(message, 96))
            // withdrawalStructOffset := mload(add(message, 100))
            // tokensArrayOffset := mload(add(message, 132))
            // middlewareTimesIndex := mload(add(message, 164))
            // receiveAsTokens := mload(add(message, 196))

            staker := mload(add(message, 228))
            delegatedTo := mload(add(message, 260))
            withdrawer := mload(add(message, 292))
            nonce := mload(add(message, 324))
            startBlock := mload(add(message, 356))

            // strategies_offset := mload(add(message, 388))
            // shares_offset := mload(add(message, 420))
            strategies_length := mload(add(message, 452))
            strategy0 := mload(add(message, 484))
            shares_length := mload(add(message, 516))
            share0 := mload(add(message, 548))
            // tokensArrayLength := mload(add(message, 580))
            // tokensToWithdraw0 := mload(add(message, 612))
        }

        IStrategy[] memory strategies = new IStrategy[](strategies_length);
        uint256[] memory shares = new uint256[](shares_length);

        strategies[0] = strategy0;
        shares[0] = share0;

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: staker,
            delegatedTo: delegatedTo,
            withdrawer: withdrawer,
            nonce: nonce,
            startBlock: startBlock,
            strategies: strategies,
            shares: shares
        });

        return withdrawal;
    }

    function _decodeCompleteWithdrawalMessagePart2(bytes memory message) internal returns (
        IERC20[] memory,
        uint256,
        bool
    ) {
        /// @note decodes the second half of the CompleteWithdrawalMessage as we run into
        /// a "stack to deep" error with more than 16 variables in the function.

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000224 [64]
        // 54b2bf29                                                         [96]
        // 0000000000000000000000000000000000000000000000000000000000000080 [100] withdrawal struct offset (129 bytes = 4 lines)
        // 00000000000000000000000000000000000000000000000000000000000001e0 [132] tokens array offset (420 bytes = 15 lines)
        // 0000000000000000000000000000000000000000000000000000000000000000 [164] middlewareTimesIndex (static var)
        // 0000000000000000000000000000000000000000000000000000000000000001 [196] receiveAsTokens (static var)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [228] struct_field_1: staker
        // 0000000000000000000000000000000000000000000000000000000000000000 [260] struct_field_2: delegatedTo
        // 0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf [292] struct_field_3: withdrawer
        // 0000000000000000000000000000000000000000000000000000000000000000 [324] struct_field_4: nonce
        // 0000000000000000000000000000000000000000000000000000000000000001 [356] struct_field_5: startBlock
        // 00000000000000000000000000000000000000000000000000000000000000e0 [388] struct_field_6: strategies[] offset (224 bytes = 7 lines)
        // 0000000000000000000000000000000000000000000000000000000000000120 [420] struct_field_7: shares[] offset (288 bytes = 9 lines)
        // 0000000000000000000000000000000000000000000000000000000000000001 [452] strategies[] length
        // 000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40af8952159 [484] strategies[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [516] shares[] length
        // 000000000000000000000000000000000000000000000000000b677a5dbaa000 [548] shares[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [580] tokens array length
        // 0000000000000000000000003eef6ec7a9679e60cc57d9688e9ec0e6624d687a [612] tokens[0] value
        // 00000000000000000000000000000000000000000000000000000000

        // bytes32 _str_offset;
        // bytes32 _str_length;
        bytes4 functionSelector;
        // uint256 withdrawalStructOffset;
        // uint256 tokensArrayOffset;
        uint256 middlewareTimesIndex;
        bool receiveAsTokens;
        // address staker;
        // address delegatedTo;
        // address withdrawer;
        // uint256 nonce;
        // uint32 startBlock;
        // uint256 strategies_offset;
        // uint256 shares_offset;
        // uint256 strategies_length;
        // IStrategy strategy0;
        // uint256 shares_length;
        // uint256 share0;
        uint256 tokensArrayLength;
        address tokensToWithdraw0;

        assembly {
            // _str_offset := mload(add(message, 32))
            // _str_length := mload(add(message, 64))
            functionSelector := mload(add(message, 96))
            // withdrawalStructOffset := mload(add(message, 100))
            // tokensArrayOffset := mload(add(message, 132))
            middlewareTimesIndex := mload(add(message, 164))
            receiveAsTokens := mload(add(message, 196))
            // staker := mload(add(message, 228))
            // delegatedTo := mload(add(message, 260))
            // withdrawer := mload(add(message, 292))
            // nonce := mload(add(message, 324))
            // startBlock := mload(add(message, 356))
            // strategies_offset := mload(add(message, 388))
            // shares_offset := mload(add(message, 420))
            // strategies_length := mload(add(message, 452))
            // strategy0 := mload(add(message, 484))
            // shares_length := mload(add(message, 516))
            // share0 := mload(add(message, 548))
            tokensArrayLength := mload(add(message, 580))
            tokensToWithdraw0 := mload(add(message, 612))
        }

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = IERC20(tokensToWithdraw0);

        console.log("middlewareTimesIndex ", middlewareTimesIndex );
        console.log("receiveAsTokens", receiveAsTokens);
        console.log("tokensToWithdraw[0]", address(tokensToWithdraw[0]));

        return (
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );
    }
}
