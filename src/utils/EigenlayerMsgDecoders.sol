//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {console} from "forge-std/Test.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
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
import {
    EigenlayerQueueWithdrawalsParams,
    EigenlayerQueueWithdrawalsWithSignatureParams
} from "../interfaces/IRestakingConnector.sol";
// TransferToStaker
import {
    TransferToStakerMessage,
    TransferToStakerParams
} from "../interfaces/IRestakingConnector.sol";
import {IEigenlayerMsgDecoders} from "../interfaces/IEigenlayerMsgDecoders.sol";


contract EigenlayerMsgDecoders is IEigenlayerMsgDecoders {

    /*
     *
     *
     *                   Deposits
     *
     *
    */

    function decodeDepositWithSignatureMessage(
        bytes memory message
    ) public returns (EigenlayerDepositWithSignatureMessage memory) {
        ////////////////////////////////////////////////////////
        //// Message payload offsets for assembly destructuring
        ////////////////////////////////////////////////////////

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000144 [64]
        // 32e89ace000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40a [96] bytes4 truncates the right
        // f8952159                                                         [100] reads 32 bytes from offset [100] right-to-left up to the function selector
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
        address _strategy;
        address token;
        uint256 amount;
        address staker;
        uint256 expiry;

        uint256 sig_offset;
        uint256 sig_length;
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

        require(sig_length == 65, "decodeDepositWithSignatureMessage: invalid signature length");

        EigenlayerDepositWithSignatureMessage memory eigenlayerDepositWithSignatureMessage;
        eigenlayerDepositWithSignatureMessage = EigenlayerDepositWithSignatureMessage({
            expiry: expiry,
            strategy: _strategy,
            token: token,
            amount: amount,
            staker: staker,
            signature: signature
        });

        emit EigenlayerDepositWithSignatureParams(amount, staker);

        return eigenlayerDepositWithSignatureMessage;
    }

    /*
     *
     *
     *                   Queue Withdrawals
     *
     *
    */

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

        emit EigenlayerQueueWithdrawalsParams(_sharesToWithdraw, _withdrawer);

        return queuedWithdrawalParams;
    }

    //////////////////////////////////////////////
    // Queue Withdrawals with Signatures
    //////////////////////////////////////////////

    function decodeQueueWithdrawalsWithSignatureMessage(
        bytes memory message
    ) public returns (
        IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory
    ) {

        /// @dev note: Need to account for bytes message including arrays of QueuedWithdrawalParams
        /// We will need to check array length in SenderCCIP to determine gas as well.
        uint256 arrayLength;
        assembly {
            arrayLength := mload(add(message, 132))
            // check correct length for QueuedWithdrawalWithSignatureParams[] array
        }

        IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory arrayQueuedWithdrawalWithSigParams =
            new IDelegationManager.QueuedWithdrawalWithSignatureParams[](arrayLength);

        console.logBytes(message);

        for (uint256 i; i < arrayLength; i++) {

            IDelegationManager.QueuedWithdrawalWithSignatureParams memory wp;
            wp = _decodeSingleQueueWithdrawalsWithSignatureMessage(message, arrayLength, i);

            arrayQueuedWithdrawalWithSigParams[i] = wp;
        }

        return arrayQueuedWithdrawalWithSigParams;
    }


    function _decodeSingleQueueWithdrawalsWithSignatureMessage(
        bytes memory message,
        uint256 arrayLength,
        uint256 i
    ) internal returns (
        IDelegationManager.QueuedWithdrawalWithSignatureParams memory
    ) {
        /// @dev: expect to use this in a for-loop

        // Function Signature:
        //     bytes5(keccak256("queueWithdrawalsWithSignature((address[],uint256[],address,address,bytes)[])"))
        // Params:
        //     queuedWithdrawalWithSig = IDelegationManager.QueuedWithdrawalWithSignatureParams({
        //         IStrategy[] strategies,
        //         uint256[] shares,
        //         address withdrawer,
        //         address staker,
        //         bytes memory signature,
        //         uint256 expiry
        //     });

        ////////////////////////////////////////////////////////
        //// Message payload offsets for assembly decoding
        ////////////////////////////////////////////////////////

        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 0000000000000000000000000000000000000000000000000000000000000224 [64] string length
        // a140f06e                                                         [96] function selector
        // 0000000000000000000000000000000000000000000000000000000000000020 [100] QueuedWithdrawWithSigParams offset
        // 0000000000000000000000000000000000000000000000000000000000000001 [132] QWWSP[] array length
        // 0000000000000000000000000000000000000000000000000000000000000020 [164] QWWSP[0] struct offset
        // 00000000000000000000000000000000000000000000000000000000000000c0 [196] struct_field_1 offset (192 bytes = 6 lines)
        // 0000000000000000000000000000000000000000000000000000000000000100 [228] struct_field_2 offset (256 bytes = 8 lines)
        // 0000000000000000000000005bf6756a91c2ce08c74fd2c50df5829ce5349317 [260] struct_field_3 withdrawer (static value)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [292] struct_field_4 staker (static value)
        // 0000000000000000000000000000000000000000000000000000000000000140 [324] struct_field_5 signature offset (320 bytes = 10 lines)
        // 0000000000000000000000000000000000000000000000000000000000005461 [356] struct_field_6 expiry
        // 0000000000000000000000000000000000000000000000000000000000000001 [388] struct_field_1 length
        // 000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40af8952159 [420] struct_field_1 value (strategy)
        // 0000000000000000000000000000000000000000000000000000000000000001 [452] struct_field_2 length
        // 00000000000000000000000000000000000000000000000000045eadb112e000 [484] struct_field_2 value (shares)
        // 0000000000000000000000000000000000000000000000000000000000000041 [516] signature length (hex 41 = 65 bytes)
        // 64e763caedbddd9837d970a9ba7d6d32ed81065e6974fbd5c25a042d05155549 [548] signature r
        // 014b117b4e37bddb7e5804cb809193d3a69d57233025728413e6c4a94208ca4a [580] signature s
        // 1c00000000000000000000000000000000000000000000000000000000000000 [612] signature v (uint8 = bytes1)
        // 00000000000000000000000000000000000000000000000000000000

        //// example with 2 elements in array
        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000404 [64]
        // a140f06e                                                         [96] function selector
        // 0000000000000000000000000000000000000000000000000000000000000020 [100] QueuedWithdrawWithSigParams offset
        // 0000000000000000000000000000000000000000000000000000000000000002 [132] QWWSP[] array length
        // 0000000000000000000000000000000000000000000000000000000000000040 [164] QWWSP[0] struct offset (2 lines)
        // 0000000000000000000000000000000000000000000000000000000000000200 [196] QWWSP[1] struct offset (200hex = 512 bytes = 16 lines)
        // 00000000000000000000000000000000000000000000000000000000000000c0 [228] struct1_field1 offset (6 lines)
        // 0000000000000000000000000000000000000000000000000000000000000100 [260] struct1_field2 offset (8 lines)
        // 0000000000000000000000007a3e017ca7ced7aaa60d5557af74063f14e64eb6 [292] struct1_field3 withdrawer (static value)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [324] struct1_field4 staker (static value)
        // 0000000000000000000000000000000000000000000000000000000000000140 [356] struct1_field5 signature offset (10 lines)
        // 0000000000000000000000000000000000000000000000000000000000015195 [388] struct1_field6 value expiry (86421 seconds)
        // 0000000000000000000000000000000000000000000000000000000000000001 [420] struct1_field1 length
        // 000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40af8952159 [452] struct1_field1 value (strategy)
        // 0000000000000000000000000000000000000000000000000000000000000001 [484] struct1_field2 length
        // 000000000000000000000000000000000000000000000000001b5b1bf4c54000 [516] struct1_field2 value (shares)
        // 0000000000000000000000000000000000000000000000000000000000000041 [548] struct1_field5 length of signature
        // 5f5b8a641b4ba45f31449d3e8eadb8defca6a7ae6ba0bebd4ff6118e122cd385 [580] struct1_field5 sig r
        // 69312cb171f2d3d475d499475192ecbbe047adad1cc0e868976bc31644407159 [612] struct1_field5 sig s
        // 1b00000000000000000000000000000000000000000000000000000000000000 [644] struct1_field5 sig v
        // 00000000000000000000000000000000000000000000000000000000000000c0 [676] struct2_field1 offset (6 lines)
        // 0000000000000000000000000000000000000000000000000000000000000100 [708] struct2_field2 offset (8 lines)
        // 0000000000000000000000007a3e017ca7ced7aaa60d5557af74063f14e64eb6 [740] struct2_field3 withdrawer (static value)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [772] struct2_field4 staker (static value)
        // 0000000000000000000000000000000000000000000000000000000000000140 [804] struct2_field5 signature offset (10 lines)
        // 0000000000000000000000000000000000000000000000000000000000015195 [836] struct2_field6 value expiry (86421 seconds)
        // 0000000000000000000000000000000000000000000000000000000000000001 [868] struct2_field1 length
        // 000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40af8952159 [900] struct2_field1 value (strategy)
        // 0000000000000000000000000000000000000000000000000000000000000001 [932] struct2_field2 length
        // 000000000000000000000000000000000000000000000000001b5b1bf4c54000 [964] struct2_field2 value (shares)
        // 0000000000000000000000000000000000000000000000000000000000000041 [996] struct2_field5 length of signature
        // 5f5b8a641b4ba45f31449d3e8eadb8defca6a7ae6ba0bebd4ff6118e122cd385 [1028] struct2_field5 sig r
        // 69312cb171f2d3d475d499475192ecbbe047adad1cc0e868976bc31644407159 [1060] struct2_field5 sig s
        // 1b00000000000000000000000000000000000000000000000000000000000000 [1092] struct2_field5 sig v
        // 00000000000000000000000000000000000000000000000000000000

        uint256 offset = ((arrayLength - 1) + (14 * i)) * 32; // offset in 32 bytes

        address _withdrawer;
        address _staker;
        uint256 _expiry;
        address _strategy;
        uint256 _sharesToWithdraw;
        bytes memory signature;

        {
            uint256 sig_length;
            bytes32 r;
            bytes32 s;
            bytes1 v;

            assembly {
                _withdrawer := mload(add(message, add(260, offset)))
                _staker := mload(add(message, add(292, offset)))
                _expiry := mload(add(message, add(356, offset)))
                _strategy := mload(add(message, add(420, offset)))
                _sharesToWithdraw := mload(add(message, add(484, offset)))

                sig_length := mload(add(message, add(516, offset)))
                r := mload(add(message, add(548, offset)))
                s := mload(add(message, add(580, offset)))
                v := mload(add(message, add(612, offset)))
            }
            // console.log("expiry");
            // console.log(_expiry);
            // console.log("withdrawer");
            // console.log(_withdrawer);
            // console.log("staker");
            // console.log(_staker);
            // console.log("_strategy");
            // console.log(_strategy);
            // console.log("_shares");
            // console.log(_sharesToWithdraw);

            signature = abi.encodePacked(r,s,v);
            require(sig_length == 65, "decodeQueueWithdrawalsWithSignatureMessage: invalid signature length");
        }

        emit EigenlayerQueueWithdrawalsWithSignatureParams(
            _sharesToWithdraw,
            _withdrawer,
            signature
        );

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](arrayLength);
        uint256[] memory sharesToWithdraw = new uint256[](arrayLength);

        strategiesToWithdraw[0] = IStrategy(_strategy);
        sharesToWithdraw[0] = _sharesToWithdraw;

        IDelegationManager.QueuedWithdrawalWithSignatureParams memory queuedWithdrawalWithSigParams;
        queuedWithdrawalWithSigParams = IDelegationManager.QueuedWithdrawalWithSignatureParams({
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw,
            withdrawer: _withdrawer,
            staker: _staker,
            signature: signature,
            expiry: _expiry
        });

        return queuedWithdrawalWithSigParams;
    }

    /*
     *
     *
     *                   Complete Withdrawals
     *
     *
    */

    function decodeCompleteWithdrawalMessage(bytes memory message) public pure returns (
        IDelegationManager.Withdrawal memory,
        IERC20[] memory,
        uint256,
        bool
    ) {
        // Note: assumes we are withdrawing 1 token, tokensToWithdraw.length == 1
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

    function _decodeCompleteWithdrawalMessagePart1(bytes memory message) internal pure returns (
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

    function _decodeCompleteWithdrawalMessagePart2(bytes memory message) internal pure returns (
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

        return (
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );
    }

    /// @dev this message is dispatched from L1 -> L2 by ReceiverCCIP.sol
    function decodeTransferToStakerMessage(
        bytes memory message
    ) public returns (TransferToStakerMessage memory) {

        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 0000000000000000000000000000000000000000000000000000000000000024 [64] string length
        // 27167d10                                                         [96] function selector
        // 8c20d3a37feccd4dcb9fa5fbd299b37db00fde77cbb7540e2850999fc7d8ec77 [100] withdrawalRoot
        // 00000000000000000000000000000000000000000000000000000000

        bytes4 functionSelector;
        bytes32 withdrawalRoot;

        assembly {
            functionSelector := mload(add(message, 96))
            withdrawalRoot := mload(add(message, 100))
        }

        TransferToStakerMessage memory transferToStakerMessage = TransferToStakerMessage({
            withdrawalRoot: withdrawalRoot
        });

        emit TransferToStakerParams(withdrawalRoot);

        return transferToStakerMessage;
    }

    /*
     *
     *
     *                   DelegateTo
     *
     *
    */

    function decodeDelegateToBySignature(
        bytes memory message
    ) public returns (
        address,
        address,
        ISignatureUtils.SignatureWithExpiry memory,
        ISignatureUtils.SignatureWithExpiry memory,
        bytes32
    ) {
        // function delegateToBySignature(
        //     address staker,
        //     address operator,
        //     SignatureWithExpiry memory stakerSignatureAndExpiry,
        //     SignatureWithExpiry memory approverSignatureAndExpiry,
        //     bytes32 approverSalt
        // )

        ////// 2x ECDSA signatures, 65 length each
        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 0000000000000000000000000000000000000000000000000000000000000224 [64] string length
        // 7f548071                                                         [96] function selector
        // 0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf [100] staker
        // 0000000000000000000000002b5ad5c4795c026514f8317c7a215e218dccd6cf [132] operator
        // 00000000000000000000000000000000000000000000000000000000000000a0 [164] staker_sig_struct offset [5 lines]
        // 0000000000000000000000000000000000000000000000000000000000000160 [196] approver_sig_struct offset [11 lines]
        // 0000000000000000000000000000000000000000000000000000000000004444 [228] approver salt
        // 0000000000000000000000000000000000000000000000000000000000000040 [260] staker_sig offset
        // 0000000000000000000000000000000000000000000000000000000000000005 [292] staker_sig expiry
        // 0000000000000000000000000000000000000000000000000000000000000041 [324] staker_sig length (hex 0x41 = 65 bytes)
        // bfb59bee8b02985b56e9c5b7cea3a900d54440b7ef0e3b41a56e6613a8bb7ead [356] staker_sig r
        // 4e082b1bb02486715bfb87b4a7202becd6df26dd4a6addb214e6748188d5e02e [388] staker_sig s
        // 1c00000000000000000000000000000000000000000000000000000000000000 [420] staker_sig v
        // 0000000000000000000000000000000000000000000000000000000000000040 [452] approver_sig offset
        // 0000000000000000000000000000000000000000000000000000000000000006 [484] approver_sig expiry
        // 0000000000000000000000000000000000000000000000000000000000000041 [516] approver_sig length (hex 41 = 65 bytes)
        // 71d0163eec33ce78295b1b94a3a43a2ea4db2219973c68ab02f16a2d88b94ce5 [548] approver_sig r
        // 3c3336c813404285f90c817c830a47facefa2a826dd33f69e14c076fbdf444b7 [580] approver_sig s
        // 1c00000000000000000000000000000000000000000000000000000000000000 [612] approver_sig v
        // 00000000000000000000000000000000000000000000000000000000

        uint256 msg_length;
        uint256 staker_sig_offset;
        uint256 approver_sig_offset;
        assembly {
            msg_length := mload(add(message, 64))
            staker_sig_offset := mload(add(message, 164))
            approver_sig_offset := mload(add(message, 196))
        }

        address staker;
        address operator;
        bytes32 approverSalt;
        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry;
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;

        assembly {
            staker := mload(add(message, 100))
            operator := mload(add(message, 132))
            approverSalt := mload(add(message, 228))
        }
        // console.log("msglen:", msg_length);
        // console.log("staker_sig_offset:", staker_sig_offset);
        // console.log("approver_sig_offset:", approver_sig_offset);
        // console.logBytes(message);

        if (msg_length == 356) {
            // staker_sig: 0
            // approver_sig: 0
            stakerSignatureAndExpiry = _getDelegationNullSignature(message, 0);
            approverSignatureAndExpiry = _getDelegationNullSignature(message, 96);

        } else if (msg_length == 452 && approver_sig_offset == 352) {
            // staker_sig: 1
            // approver_sig: 0

            // 0000000000000000000000000000000000000000000000000000000000000020
            // 00000000000000000000000000000000000000000000000000000000000001c4
            // 7f548071
            // 0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf
            // 0000000000000000000000002b5ad5c4795c026514f8317c7a215e218dccd6cf
            // 00000000000000000000000000000000000000000000000000000000000000a0 [164] staker_sig_struct offset [5 lines]
            // 0000000000000000000000000000000000000000000000000000000000000160 [196] approver_sig_struct offset [11 lines]
            // 0000000000000000000000000000000000000000000000000000000000004444 [228]
            // 0000000000000000000000000000000000000000000000000000000000000040 [260] staker_sig offset
            // 0000000000000000000000000000000000000000000000000000000000000005 [292]
            // 0000000000000000000000000000000000000000000000000000000000000041 [324] staker_sig length
            // bfb59bee8b02985b56e9c5b7cea3a900d54440b7ef0e3b41a56e6613a8bb7ead
            // 4e082b1bb02486715bfb87b4a7202becd6df26dd4a6addb214e6748188d5e02e
            // 1c00000000000000000000000000000000000000000000000000000000000000
            // 0000000000000000000000000000000000000000000000000000000000000040 [452] approver_sig offset
            // 0000000000000000000000000000000000000000000000000000000000000006
            // 0000000000000000000000000000000000000000000000000000000000000000
            // 00000000000000000000000000000000000000000000000000000000

            stakerSignatureAndExpiry = _getDelegationSignature(message, 0);
            approverSignatureAndExpiry = _getDelegationNullSignature(message, 192); // 96 offset more

        } else if (msg_length == 452 && approver_sig_offset == 256) {
            // staker_sig: 0
            // approver_sig: 1
            stakerSignatureAndExpiry = _getDelegationNullSignature(message, 0);
            approverSignatureAndExpiry = _getDelegationSignature(message, 96);

        } else if (msg_length == 548) {
            // staker_sig: 1
            // approver_sig: 1
            stakerSignatureAndExpiry = _getDelegationSignature(message, 0);
            // 192 offset for approver signature
            approverSignatureAndExpiry = _getDelegationSignature(message, 192);
        }

        return (
            staker,
            operator,
            stakerSignatureAndExpiry,
            approverSignatureAndExpiry,
            approverSalt
        );
    }


    function _getDelegationSignature(
        bytes memory message,
        uint256 offset
    ) internal returns (ISignatureUtils.SignatureWithExpiry memory) {

        uint256 expiry;
        bytes memory signature;
        bytes32 r;
        bytes32 s;
        bytes1 v;

        assembly {
            expiry := mload(add(message, add(292, offset)))
            r := mload(add(message, add(356, offset)))
            s := mload(add(message, add(388, offset)))
            v := mload(add(message, add(420, offset)))
        }

        signature = abi.encodePacked(r, s, v);

        ISignatureUtils.SignatureWithExpiry memory signatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
            signature: signature,
            expiry: expiry
        });

        return signatureAndExpiry;
    }


    function _getDelegationNullSignature(
        bytes memory message,
        uint256 offset
    ) internal returns (ISignatureUtils.SignatureWithExpiry memory) {

        ///// Null signatures:
        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000164 [64]
        // 7f548071                                                         [96]
        // 0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf [100] staker
        // 0000000000000000000000002b5ad5c4795c026514f8317c7a215e218dccd6cf [132] operator
        // 00000000000000000000000000000000000000000000000000000000000000a0 [164] staker_sig_struct offset [5 lines]
        // 0000000000000000000000000000000000000000000000000000000000000100 [196] approver_sig_struct offset [8 lines]
        // 0000000000000000000000000000000000000000000000000000000000004444 [228] approverSalt
        // 0000000000000000000000000000000000000000000000000000000000000040 [260] staker_sig offset (bytes has a offset and length)
        // 0000000000000000000000000000000000000000000000000000000000000005 [292] staker_sig expiry
        // 0000000000000000000000000000000000000000000000000000000000000000 [324] staker_signature
        // 0000000000000000000000000000000000000000000000000000000000000040 [356] approver_sig offset
        // 0000000000000000000000000000000000000000000000000000000000000006 [388] approver_sig expiry
        // 0000000000000000000000000000000000000000000000000000000000000000 [420] approver_signature
        // 00000000000000000000000000000000000000000000000000000000

        uint256 expiry;
        bytes memory signature;

        assembly {
            expiry := mload(add(message, add(292, offset)))
            signature := mload(add(message, add(324, offset)))
        }

        ISignatureUtils.SignatureWithExpiry memory signatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
            signature: signature,
            expiry: expiry
        });

        return signatureAndExpiry;
    }


    function decodeUndelegate(
        bytes memory message
    ) public returns (address) {

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000224 [64]
        // 54b2bf29                                                         [96]
        // 00000000000000000000000071c6f7ed8c2d4925d0baf16f6a85bb1736d412eb [100] address
        // 00000000000000000000000000000000000000000000000000000000

        bytes4 functionSelector;
        address staker;

        assembly {
            functionSelector := mload(add(message, 96))
            staker := mload(add(message, 100))
        }

        return staker;
    }

}
