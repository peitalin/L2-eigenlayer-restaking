//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EigenlayerMsgEncoders} from "./EigenlayerMsgEncoders.sol";


struct EigenlayerDeposit6551Msg {
    address strategy;
    address token;
    uint256 amount;
    address staker;
    uint256 expiry;
    bytes signature;
}
event EigenlayerDeposit6551Params(
    address indexed staker,
    address indexed strategy,
    address token,
    uint256 indexed amount
);

event EigenlayerQueueWithdrawalsParams(
    uint256 indexed amount,
    address indexed staker
);

struct TransferToAgentOwnerMsg {
    bytes32 withdrawalRoot;
    address agentOwner;
    bytes32 agentOwnerRoot;
}
event TransferToAgentOwnerParams(
    bytes32 indexed withdrawalRoot,
    address indexed agentOwner,
    bytes32 indexed agentOwnerRoot
);


library EigenlayerMsgDecoders {

    /*
     *
     *
     *                   Deposits
     *
     *
    */

    function decodeDepositWithSignature6551Msg(bytes memory message)
        public pure
        returns (EigenlayerDeposit6551Msg memory)
    {
        ////////////////////////////////////////////////////////
        //// Msg payload offsets for assembly destructuring
        ////////////////////////////////////////////////////////

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000144 [64]
        // 32e89ace                                                         [96] bytes4 truncates the right
        // 000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40af8952159 [100] reads 32 bytes from offset [100] right-to-left up to the function selector
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

        address strategy;
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

        bytes memory signature = abi.encodePacked(r,s,v);

        require(sig_length == 65, "decodeDepositWithSignature6551Msg: invalid signature length");

        return EigenlayerDeposit6551Msg({
            strategy: strategy,
            token: token,
            amount: amount,
            staker: staker,
            expiry: expiry,
            signature: signature
        });
    }

    function decodeDepositMsg(bytes memory message)
        public pure
        returns (address, address, uint256)
    {
        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000144 [64]
        // 32e89ace                                                         [96] bytes4 truncates the right
        // 000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40af8952159 [100] reads 32 bytes from offset [100] right-to-left up to the function selector
        // 0000000000000000000000003eef6ec7a9679e60cc57d9688e9ec0e6624d687a [132]
        // 000000000000000000000000000000000000000000000000001b5b1bf4c54000 [164] uint256 amount in hex
        // 00000000000000000000000000000000000000000000000000000000

        address strategy;
        address token;
        uint256 amount;

        assembly {
            strategy := mload(add(message, 100))
            token := mload(add(message, 132))
            amount := mload(add(message, 164))
        }

        return (strategy, token, amount);
    }


    /*
     *
     *
     *                   Queue Withdrawals
     *
     *
    */

    function decodeQueueWithdrawalsMsg(bytes memory message)
        public pure
        returns (
            IDelegationManager.QueuedWithdrawalParams[] memory,
            uint256,
            bytes memory
        )
    {
        /// @dev note: Need to account for bytes message including arrays of QueuedWithdrawalParams
        /// We will need to check array length in SenderCCIP to determine gas as well.

        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 00000000000000000000000000000000000000000000000000000000000001a5 [64] string length
        // 0dd8dd02                                                         [96] function selector
        // 0000000000000000000000000000000000000000000000000000000000000020 [100] array offset
        // 0000000000000000000000000000000000000000000000000000000000000001 [132] array length
        // 0000000000000000000000000000000000000000000000000000000000000020 [164] struct1 offset
        // 0000000000000000000000000000000000000000000000000000000000000060 [196] struct1_field1 offset (strategies)
        // 00000000000000000000000000000000000000000000000000000000000000a0 [228] struct1_field2 offset (shares)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [260] struct1_field3 (withdrawer)
        // 0000000000000000000000000000000000000000000000000000000000000001 [292] struct1_field1 length
        // 000000000000000000000000b111111ad20e9d85d5152ae68f45f40a11111111 [324] struct1_field1 value (strategies[0])
        // 0000000000000000000000000000000000000000000000000000000000000001 [356] struct1_field2 length
        // 0000000000000000000000000000000000000000000000000023e2ce54e05000 [388] struct1_field2 value (shares[0])
        // 00000000000000000000000000000000000000000000000000000000424b2a0e [420] expiry
        // 1f7c77a6b0940a7ce34edf2821d323701213db8e237c46fdf8b7bedc8f295359 [452] signature r
        // 1b82b0bd80af2140d658af1312ba94049de6c699533bca58da0f29d659cdf61a [484] signature s
        // 1c000000000000000000000000000000000000000000000000000000         [516] signature v

        uint256 arrayLength;
        assembly {
            arrayLength := mload(add(message, 132))
        }

        require(arrayLength >= 1, "decodeQueueWithdrawalsMsg: arrayLength must be at least 1");

        IDelegationManager.QueuedWithdrawalParams[] memory arrayQueuedWithdrawalParams =
            new IDelegationManager.QueuedWithdrawalParams[](arrayLength);

        for (uint256 i; i < arrayLength; i++) {
            IDelegationManager.QueuedWithdrawalParams memory wp;
            wp = _decodeSingleQueueWithdrawalMsg(message, arrayLength, i);
            arrayQueuedWithdrawalParams[i] = wp;
        }

        uint256 expiry;
        bytes32 r;
        bytes32 s;
        bytes1 v;

        // note: Each extra QueuedWithdrawalParam element adds 1x offset and 7 lines:
        // So when reading the signature, increase offset by 7 * i:
        //      1 element:  offset = (1 - 1) * (1 + 7) = 0
        //      2 elements: offset = (2 - 1) * (1 + 7) = 8
        //      3 elements: offset = (3 - 1) * (1 + 7) = 16
        uint256 offset = (arrayLength - 1) * (1 + 7) * 32; // 32 bytes per line

        assembly {
            expiry := mload(add(message, add(420, offset)))
            r := mload(add(message, add(452, offset)))
            s := mload(add(message, add(484, offset)))
            v := mload(add(message, add(516, offset)))
        }

        bytes memory signature = abi.encodePacked(r,s,v);

        return (arrayQueuedWithdrawalParams, expiry, signature);
    }

    function _decodeSingleQueueWithdrawalMsg(bytes memory message, uint256 arrayLength, uint256 i)
        internal pure
        returns (IDelegationManager.QueuedWithdrawalParams memory)
    {
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

        bytes4 functionSelector;
        address _withdrawer;
        address _strategy;
        uint256 _sharesToWithdraw;

        // Every extra element in the QueueWithdrawalParams[] array adds
        // 1x struct offset (1 line) and (7 lines), so shift everything down by:
        uint256 offset = (arrayLength - 1) + (7 * i);

        // So when reading the ith element, increase offset by 7 * i:
        //      1 element:  offset = (1 - 1) + (7 * 0) = 0
        //      2 elements: offset = (2 - 1) + (7 * 1) = 8
        //      3 elements: offset = (3 - 1) + (7 * 2) = 16

        uint256 withdrawerOffset = 260 + offset * 32;
        uint256 strategyOffset = 324 + offset * 32;
        uint256 sharesToWithdrawOffset = 388 + offset * 32;

        assembly {
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

        return queuedWithdrawalParams;
    }

    //////////////////////////////////////////////
    // Queue Withdrawals with Signatures
    //////////////////////////////////////////////

    /*
     *
     *
     *                   Complete Withdrawals
     *
     *
    */

    function decodeCompleteWithdrawalMsg(bytes memory message)
        public pure
        returns (
            IDelegationManager.Withdrawal memory,
            IERC20[] memory,
            uint256,
            bool,
            uint256,
            bytes memory
        )
    {
        // Note: assumes we are withdrawing 1 token, tokensToWithdraw.length == 1
        IDelegationManager.Withdrawal memory _withdrawal = _decodeCompleteWithdrawalMsgPart1(message);
        (
            IERC20[] memory _tokensToWithdraw,
            uint256 _middlewareTimesIndex,
            bool _receiveAsTokens,
            uint256 _expiry,
            bytes memory _signature
        ) = _decodeCompleteWithdrawalMsgPart2(message);

        return (
            _withdrawal,
            _tokensToWithdraw,
            _middlewareTimesIndex,
            _receiveAsTokens,
            _expiry,
            _signature
        );
    }

    function _decodeCompleteWithdrawalMsgPart1(bytes memory message)
        internal pure
        returns (IDelegationManager.Withdrawal memory)
    {
        /// @note decodes the first half of the CompleteWithdrawalMsg as we run into
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

    function _decodeCompleteWithdrawalMsgPart2(bytes memory message)
        internal pure
        returns (
            IERC20[] memory,
            uint256,
            bool,
            uint256,
            bytes memory
        )
    {
        /// @note decodes the second half of the CompleteWithdrawalMsg as we run into
        /// a "stack to deep" error with more than 16 variables in the function.

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000285 [64]
        // 54b2bf29                                                         [96]
        // 0000000000000000000000000000000000000000000000000000000000000080 [100] withdrawal struct offset (129 bytes = 4 lines)
        // 00000000000000000000000000000000000000000000000000000000000001e0 [132] tokens array offset (420 bytes = 15 lines)
        // 0000000000000000000000000000000000000000000000000000000000000000 [164] middlewareTimesIndex (static var)
        // 0000000000000000000000000000000000000000000000000000000000000001 [196] receiveAsTokens (static var)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [228] struct_field_1: staker
        // 0000000000000000000000000000000000000000000000000000000000000000 [260] struct_field_2: delegatedTo
        // 0000000000000000000000004c854b17250582413783b96e020e5606a561eddc [292] struct_field_3: withdrawer
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
        // 00000000000000000000000000000000000000000000000000000000424b2a0e [644] expiry
        // 1f7c77a6b0940a7ce34edf2821d323701213db8e237c46fdf8b7bedc8f295359 [676] signature r
        // 1b82b0bd80af2140d658af1312ba94049de6c699533bca58da0f29d659cdf61a [708] signature s
        // 1c000000000000000000000000000000000000000000000000000000         [740] signature v

        // 1f7c77a6b0940a7ce34edf2821d323701213db8e237c46fdf8b7bedc8f295359
        // 1b82b0bd80af2140d658af1312ba94049de6c699533bca58da0f29d659cdf61a
        // 00

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

        uint256 expiry;
        bytes32 r;
        bytes32 s;
        bytes1 v;

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

            expiry := mload(add(message, 644))
            r := mload(add(message, 676))
            s := mload(add(message, 708))
            v := mload(add(message, 740))
        }

        bytes memory signature = abi.encodePacked(r,s,v);

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = IERC20(tokensToWithdraw0);

        return (
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens,
            expiry,
            signature
        );
    }


    /// @dev this message is dispatched from L1 -> L2 by ReceiverCCIP.sol
    function decodeTransferToAgentOwnerMsg(bytes memory message)
        public pure
        returns (TransferToAgentOwnerMsg memory)
    {
        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 0000000000000000000000000000000000000000000000000000000000000024 [64] string length
        // 27167d10                                                         [96] function selector
        // 8c20d3a37feccd4dcb9fa5fbd299b37db00fde77cbb7540e2850999fc7d8ec77 [100] withdrawalRoot
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [132] agent owner
        // 00000000000000000000000000000000000000000000000000000000

        bytes4 functionSelector;
        bytes32 withdrawalRoot;
        address agentOwner;

        assembly {
            functionSelector := mload(add(message, 96))
            withdrawalRoot := mload(add(message, 100))
            agentOwner := mload(add(message, 132))
        }

        bytes32 agentOwnerRoot = EigenlayerMsgEncoders.calculateAgentOwnerRoot(withdrawalRoot, agentOwner);

        TransferToAgentOwnerMsg memory toAgentOwnerMsg = TransferToAgentOwnerMsg({
            withdrawalRoot: withdrawalRoot,
            agentOwner: agentOwner,
            agentOwnerRoot: agentOwnerRoot
        });

        return toAgentOwnerMsg;
    }

    /*
     *
     *
     *                   DelegateTo
     *
     *
    */

    function decodeDelegateToBySignatureMsg(bytes memory message)
        public pure
        returns (
            address,
            address,
            ISignatureUtils.SignatureWithExpiry memory,
            ISignatureUtils.SignatureWithExpiry memory,
            bytes32
        )
    {
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


    function _getDelegationSignature(bytes memory message, uint256 offset)
        internal pure
        returns (ISignatureUtils.SignatureWithExpiry memory)
    {

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


    function _getDelegationNullSignature(bytes memory message, uint256 offset)
        internal pure
        returns (ISignatureUtils.SignatureWithExpiry memory)
    {

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


    function decodeUndelegateMsg(bytes memory message)
        public pure
        returns (address)
    {
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
