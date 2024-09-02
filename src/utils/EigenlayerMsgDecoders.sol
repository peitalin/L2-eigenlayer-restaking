//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct TransferToAgentOwnerMsg {
    bytes32 withdrawalRoot;
}

/// @dev used to decode user signatures on all CCIP messages to EigenAgents
library AgentOwnerSignature {

    function decodeAgentOwnerSignature(bytes memory message, uint256 sigOffset)
        public pure
        returns (
            address signer,
            uint256 expiry,
            bytes memory signature
        )
    {

        bytes32 r;
        bytes32 s;
        bytes1 v;

        assembly {
            signer := mload(add(message, sigOffset))
            expiry := mload(add(message, add(sigOffset, 32)))
            r := mload(add(message, add(sigOffset, 64)))
            s := mload(add(message, add(sigOffset, 96)))
            v := mload(add(message, add(sigOffset, 128)))
        }

        signature = abi.encodePacked(r, s, v);

        return (
            signer,
            expiry,
            signature
        );
    }
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

        assembly {
            strategy := mload(add(message, 100))
            token := mload(add(message, 132))
            amount := mload(add(message, 164))
        }

        (
            signer,
            expiry,
            signature
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, 196); // signature starts on 196

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

        // note: Each extra QueuedWithdrawalParam element adds 1x offset and 7 lines:
        // So when reading the signature, increase offset by 7 * i:
        //      1 element:  offset = (1 - 1) * (1 + 7) = 0
        //      2 elements: offset = (2 - 1) * (1 + 7) = 8
        //      3 elements: offset = (3 - 1) * (1 + 7) = 16
        uint256 offset = (arrayLength - 1) * (1 + 7) * 32; // 32 bytes per line

        (
            signer,
            expiry,
            signature
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, 420 + offset); // signature starts on 420 + offset

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
        }

        (
            signer,
            expiry,
            signature
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, 644); // signature (signer) starts at 644

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

        // 0000000000000000000000000000000000000000000000000000000000000020
        // 0000000000000000000000000000000000000000000000000000000000000064
        // d8a85b48                                                         [96] function selector
        // dd900ac4d233ec9d74ac5af4ce89f87c78781d8fd9ee2aad62d312bdfdf78a14 [100] withdrawal root
        // 00000000000000000000000000000000000000000000000000000000

        bytes4 functionSelector;
        bytes32 withdrawalRoot;
        // address agentOwner;
        // bytes32 agentOwnerRoot;

        assembly {
            functionSelector := mload(add(message, 96))
            withdrawalRoot := mload(add(message, 100))
            // agentOwner := mload(add(message, 132))
            // agentOwnerRoot := mload(add(message, 164))
        }

        return TransferToAgentOwnerMsg({
            withdrawalRoot: withdrawalRoot
        });
    }
}

/*
 *
 *
 *                   DelegateTo
 *
 *
 */

library DelegationDecoders {

    function decodeDelegateToMsg(bytes memory message)
        public pure
        returns (
            address operator,
            ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
            bytes32 approverSalt,
            address signer,
            uint256 expiryEigenAgent,
            bytes memory signatureEigenAgent
        )
    {
        // function delegateTo(
        //     address operator,
        //     SignatureWithExpiry memory approverSignatureAndExpiry,
        //     bytes32 approverSalt
        // )

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000124 [64]
        // eea9064b                                                         [96]
        // 000000000000000000000000722551f573d58c97893286f8f00e76119501ae37 [100] operator
        // 0000000000000000000000000000000000000000000000000000000000000060 [132] approverSigExpiry struct offset
        // 000000000000000000000000000000000000000000000000000000000153158e [164] approverSalt
        // 0000000000000000000000000000000000000000000000000000000000000040 [196] approverSigExpiry.sig offset
        // 0000000000000000000000000000000000000000000000000000000066d3a91c [228] sig expiry
        // 0000000000000000000000000000000000000000000000000000000000000041 [260] approverSigExpiry.sig length (hex 41 = 65 bytes)
        // d2ec2451a264124b3966b82aad0e40e9517175affad9f23d600dbddfff57db4d [292] sig r
        // 62440bdea7d1a009fb374773868853d52e7425035fddfff0256c26650dcfed34 [324] sig s
        // 1c00000000000000000000000000000000000000000000000000000000000000 [356] sig v
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [388] eigenAgent signer
        // 0000000000000000000000000000000000000000000000000000000066d3b834 [420] eigenAgent sig expiry
        // e00176f55bcbdf4f335018dc3b676b349c938a51804d3f0d78d02f75f77b85c1 [452] eigenAgent sig r
        // 78060931402acbf07ebbe20d1648a2b3072ad508523d947a0eee31cdd386d6fd [484] eigenAgent sig s
        // 1c000000000000000000000000000000000000000000000000000000         [516] eigenAgent sig v

        uint256 sigExpiry;

        bytes32 r;
        bytes32 s;
        bytes1  v;

        assembly {
            operator := mload(add(message, 100))
            approverSalt := mload(add(message, 164))

            sigExpiry := mload(add(message, 228))
            r := mload(add(message, 292))
            s := mload(add(message, 324))
            v := mload(add(message, 356))
        }

        bytes memory signatureOperatorApprover = abi.encodePacked(r, s, v);

        approverSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
            signature: signatureOperatorApprover,
            expiry: sigExpiry
        });

        (
            signer,
            expiryEigenAgent,
            signatureEigenAgent
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, 388); // user signature starts on 388

        require(signatureEigenAgent.length == 65, "decodeDelegateToMsg: invalid signature length");

        return (
            // original message for Eigenlayer
            operator,
            approverSignatureAndExpiry,
            approverSalt,
            // signature for EigenAgent execution
            signer,
            expiryEigenAgent,
            signatureEigenAgent
        );
    }

    function decodeUndelegateMsg(bytes memory message)
        public pure
        returns (
            address staker, // eigenAgent
            address signer,
            uint256 expiryEigenAgent,
            bytes memory signatureEigenAgent
        )
    {

        // 0000000000000000000000000000000000000000000000000000000000000020
        // 00000000000000000000000000000000000000000000000000000000000000a5
        // da8be864                                                         [96] function selector
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [100] staker address (delegating)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [132] eigenAgent signer
        // 0000000000000000000000000000000000000000000000000000000000000e11 [164] eigenAgent sig expiry
        // b20a886dfc3208a956b14419e367c1127258b8079559b101a7d6ced1271d464f [196] eigenAgent sig r
        // 271a38b87fd2cd30f183d542483cc71269711bdc9044b24baf2b7aa189a3d1e0 [228] eigenAgent sig s
        // 1c000000000000000000000000000000000000000000000000000000         [260] eigenAgent sig v


        bytes4 functionSelector;

        assembly {
            functionSelector := mload(add(message, 96))
            staker := mload(add(message, 100))
        }

        (
            signer,
            expiryEigenAgent,
            signatureEigenAgent
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, 132);

        return (
            staker,
            signer,
            expiryEigenAgent,
            signatureEigenAgent
        );
    }
}