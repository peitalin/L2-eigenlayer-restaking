//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EigenlayerMsgEncoders} from "./EigenlayerMsgEncoders.sol";


struct TransferToAgentOwnerMsg {
    bytes32 withdrawalRoot;
    address agentOwner;
    bytes32 agentOwnerRoot;
}

contract EigenlayerMsgDecoders {

    /*
     *
     *
     *                   Deposits
     *
     *
    */

    function decodeDepositWithSignature6551Msg(bytes memory message)
        public pure
        returns (
            address strategy,
            address token,
            uint256 amount,
            address signer,
            uint256 expiry,
            bytes memory signature
        )
    {
        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 00000000000000000000000000000000000000000000000000000000000000e5 [64] string length
        // e7a050aa                                                         [96] function selector
        // 000000000000000000000000e642c43b2a7d4510233a30f7695f437878bfee09 [100] strategy
        // 000000000000000000000000fd57b4ddbf88a4e07ff4e34c487b99af2fe82a05 [132] token
        // 000000000000000000000000000000000000000000000000002f40478f834000 [164] amount
        // 000000000000000000000000ff56509f4a1992c52577408cd2075b8a8531dc0a [196] signer (original staker)
        // 0000000000000000000000000000000000000000000000000000000066d063d4 [228] expiry (signature)
        // b65bb77203b002de051363fd17437187540d5c6a0cfcb75c31dfffff9108e41d [260] signature r
        // 037e6bdadf2079e5268e5ad0000699611e63c3e015027ad7f8e7b4a252bbb9bb [292] signature s
        // 1c000000000000000000000000000000000000000000000000000000         [324] signature v

        bytes32 r;
        bytes32 s;
        bytes1 v;

        assembly {
            strategy := mload(add(message, 100))
            token := mload(add(message, 132))
            amount := mload(add(message, 164))

            signer := mload(add(message, 196))
            expiry := mload(add(message, 228))
            r := mload(add(message, 260))
            s := mload(add(message, 292))
            v := mload(add(message, 324))
        }

        signature = abi.encodePacked(r,s,v);

        require(signature.length == 65, "decodeDepositWithSignature6551Msg: invalid signature length");

        return (
            strategy,
            token,
            amount,
            signer,
            expiry,
            signature
        );
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
            IDelegationManager.QueuedWithdrawalParams[] memory arrayQueuedWithdrawalParams,
            address signer,
            uint256 expiry,
            bytes memory signature
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
        // 000000000000000000000000b2d4f7219a47c841543ee8ca37d9ca94db49fe1c [260] struct1_field3 (withdrawer)
        // 0000000000000000000000000000000000000000000000000000000000000001 [292] struct1_field1 length
        // 000000000000000000000000b111111ad20e9d85d5152ae68f45f40a11111111 [324] struct1_field1 value (strategies[0])
        // 0000000000000000000000000000000000000000000000000000000000000001 [356] struct1_field2 length
        // 0000000000000000000000000000000000000000000000000023e2ce54e05000 [388] struct1_field2 value (shares[0])
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [420] signer (original staker)
        // 00000000000000000000000000000000000000000000000000000000424b2a0e [452] expiry
        // 1f7c77a6b0940a7ce34edf2821d323701213db8e237c46fdf8b7bedc8f295359 [484] signature r
        // 1b82b0bd80af2140d658af1312ba94049de6c699533bca58da0f29d659cdf61a [516] signature s
        // 1c000000000000000000000000000000000000000000000000000000         [548] signature v

        uint256 arrayLength;
        assembly {
            arrayLength := mload(add(message, 132))
        }

        require(arrayLength >= 1, "decodeQueueWithdrawalsMsg: arrayLength must be at least 1");

        arrayQueuedWithdrawalParams = new IDelegationManager.QueuedWithdrawalParams[](arrayLength);

        for (uint256 i; i < arrayLength; i++) {
            IDelegationManager.QueuedWithdrawalParams memory wp;
            wp = _decodeSingleQueueWithdrawalMsg(message, arrayLength, i);
            arrayQueuedWithdrawalParams[i] = wp;
        }

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
            signer := mload(add(message, add(420, offset)))
            expiry := mload(add(message, add(452, offset)))
            r := mload(add(message, add(484, offset)))
            s := mload(add(message, add(516, offset)))
            v := mload(add(message, add(548, offset)))
        }

        signature = abi.encodePacked(r,s,v);

        return (
            arrayQueuedWithdrawalParams,
            signer,
            expiry,
            signature
        );
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
            IDelegationManager.Withdrawal memory withdrawal,
            IERC20[] memory tokensToWithdraw,
            uint256 middlewareTimesIndex,
            bool receiveAsTokens,
            address signer,
            uint256 expiry,
            bytes memory signature
        )
    {
        // Note: assumes we are withdrawing 1 token, tokensToWithdraw.length == 1
        withdrawal = _decodeCompleteWithdrawalMsgPart1(message);

        (
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens,
            signer,
            expiry,
            signature
        ) = _decodeCompleteWithdrawalMsgPart2(message);

        return (
            withdrawal,
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens,
            signer,
            expiry,
            signature
        );
    }

    function _decodeCompleteWithdrawalMsgPart1(bytes memory message)
        internal pure
        returns (IDelegationManager.Withdrawal memory)
    {
        /// @note decodes the first half of the CompleteWithdrawalMsg as we run into
        /// a "stack to deep" error with more than 16 variables in the function.

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 00000000000000000000000000000000000000000000000000000000000002a5 [64]
        // 60d7faed                                                         [96]
        // 0000000000000000000000000000000000000000000000000000000000000080 [100] withdrawal struct offset (129 bytes = 4 lines)
        // 00000000000000000000000000000000000000000000000000000000000001e0 [132] tokens array offset (480 bytes = 15 lines)
        // 0000000000000000000000000000000000000000000000000000000000000000 [164] middlewareTimesIndex (static var)
        // 0000000000000000000000000000000000000000000000000000000000000001 [196] receiveAsTokens (static var)
        // 000000000000000000000000b6b60fb7c880824a3a98d3ddc783662afb1f34cb [228] struct_field_1: staker
        // 0000000000000000000000000000000000000000000000000000000000000000 [260] struct_field_2: delegatedTo
        // 000000000000000000000000b6b60fb7c880824a3a98d3ddc783662afb1f34cb [292] struct_field_3: withdrawer
        // 0000000000000000000000000000000000000000000000000000000000000000 [324] struct_field_4: nonce
        // 000000000000000000000000000000000000000000000000000000000064844f [356] struct_field_5: startBlock
        // 00000000000000000000000000000000000000000000000000000000000000e0 [388] struct_field_6: strategies[] offset (224 bytes = 7 lines)
        // 0000000000000000000000000000000000000000000000000000000000000120 [420] struct_field_7: shares[] offset (9 lines)
        // 0000000000000000000000000000000000000000000000000000000000000001 [452] strategies[] length
        // 000000000000000000000000e642c43b2a7d4510233a30f7695f437878bfee09 [484] strategies[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [516] shares[] length
        // 000000000000000000000000000000000000000000000000002f40478f834000 [548] shares[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [580] tokens[] length
        // 000000000000000000000000fd57b4ddbf88a4e07ff4e34c487b99af2fe82a05 [612] tokens[0] value
        // 000000000000000000000000ff56509f4a1992c52577408cd2075b8a8531dc0a [644] signer (orignal staker, EigenAgent owner)
        // 0000000000000000000000000000000000000000000000000000000066d06d10 [676] expiry
        // 7248f3afe32860eb361e7e4f5d43d67fe7a93961c22f23d3121bbd5c23a18f7d [708] signature r
        // 7dc2083830eb5273eff83f1741080f1530162a10eafcdb848c05dcf146a9ab1f [740] signature s
        // 1b000000000000000000000000000000000000000000000000000000         [772] signature v

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
            IERC20[] memory tokensToWithdraw,
            uint256 middlewareTimesIndex,
            bool receiveAsTokens,
            address signer,
            uint256 expiry,
            bytes memory signature
        )
    {
        /// @note decodes the second half of the CompleteWithdrawalMsg to avoid
        /// a "stack to deep" error with too many variables in the function.

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 00000000000000000000000000000000000000000000000000000000000002a5 [64]
        // 60d7faed                                                         [96]
        // 0000000000000000000000000000000000000000000000000000000000000080 [100] withdrawal struct offset (129 bytes = 4 lines)
        // 00000000000000000000000000000000000000000000000000000000000001e0 [132] tokens array offset (480 bytes = 15 lines)
        // 0000000000000000000000000000000000000000000000000000000000000000 [164] middlewareTimesIndex (static var)
        // 0000000000000000000000000000000000000000000000000000000000000001 [196] receiveAsTokens (static var)
        // 000000000000000000000000b6b60fb7c880824a3a98d3ddc783662afb1f34cb [228] struct_field_1: staker
        // 0000000000000000000000000000000000000000000000000000000000000000 [260] struct_field_2: delegatedTo
        // 000000000000000000000000b6b60fb7c880824a3a98d3ddc783662afb1f34cb [292] struct_field_3: withdrawer
        // 0000000000000000000000000000000000000000000000000000000000000000 [324] struct_field_4: nonce
        // 000000000000000000000000000000000000000000000000000000000064844f [356] struct_field_5: startBlock
        // 00000000000000000000000000000000000000000000000000000000000000e0 [388] struct_field_6: strategies[] offset (224 bytes = 7 lines)
        // 0000000000000000000000000000000000000000000000000000000000000120 [420] struct_field_7: shares[] offset (9 lines)
        // 0000000000000000000000000000000000000000000000000000000000000001 [452] strategies[] length
        // 000000000000000000000000e642c43b2a7d4510233a30f7695f437878bfee09 [484] strategies[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [516] shares[] length
        // 000000000000000000000000000000000000000000000000002f40478f834000 [548] shares[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [580] tokens[] length
        // 000000000000000000000000fd57b4ddbf88a4e07ff4e34c487b99af2fe82a05 [612] tokens[0] value
        // 000000000000000000000000ff56509f4a1992c52577408cd2075b8a8531dc0a [644] signer (original staker, EigenAgent owner)
        // 0000000000000000000000000000000000000000000000000000000066d06d10 [676] expiry
        // 7248f3afe32860eb361e7e4f5d43d67fe7a93961c22f23d3121bbd5c23a18f7d [708] signature r
        // 7dc2083830eb5273eff83f1741080f1530162a10eafcdb848c05dcf146a9ab1f [740] signature s
        // 1b000000000000000000000000000000000000000000000000000000         [772] signature v

        uint256 tokensArrayLength;
        address tokensToWithdraw0;
        bytes32 r;
        bytes32 s;
        bytes1 v;

        assembly {
            // _str_offset := mload(add(message, 32))
            // _str_length := mload(add(message, 64))
            // functionSelector := mload(add(message, 96))
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

            signer := mload(add(message, 644))
            expiry := mload(add(message, 676))
            r := mload(add(message, 708))
            s := mload(add(message, 740))
            v := mload(add(message, 772))
        }

        signature = abi.encodePacked(r,s,v);
        tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = IERC20(tokensToWithdraw0);

        return (
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens,
            signer,
            expiry,
            signature
        );
    }


    /// @dev this message is dispatched from L1 -> L2 by ReceiverCCIP.sol
    function decodeTransferToAgentOwnerMsg(bytes memory message)
        public pure
        returns (TransferToAgentOwnerMsg memory transferToAgentOwnerMsg)
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

        return TransferToAgentOwnerMsg({
            withdrawalRoot: withdrawalRoot,
            agentOwner: agentOwner,
            agentOwnerRoot: agentOwnerRoot
        });
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
