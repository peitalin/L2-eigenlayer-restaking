//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {console} from "forge-std/Test.sol";


struct TransferToAgentOwnerMsg {
    bytes32 withdrawalTransferRoot;
}

library AgentOwnerSignature {

    /**
     * @dev Decodes user signatures on all CCIP messages to EigenAgents
     * @param message is a CCIP message to Eigenlayer
     * @param sigOffset is the offset where the user signature begins
     */
    function decodeAgentOwnerSignature(bytes memory message, uint256 sigOffset)
        public
        pure
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

    /**
    * @param message CCIP message to Eigenlayer
    * @return strategy Eigenlayer strategy vault user is depositing into.
    * @return token Token address associated with the strategy.
    * @return amount Amount user is depositing
    * @return signer Owner of the EigenAgent
    * @return expiry Determines when a cross chain deposit can be refunded.
    * If a deposit is stuck in CCIP after bridging, user may manually trigger a refund after expiry.
    * @return signature Signed by the user for their EigenAgent to excecute.
    * The signature signs a hash of the message being sent to Eigenlayer.
    */
    function decodeDepositIntoStrategyMsg(bytes memory message)
        public
        pure
        returns (
            address strategy,
            address token,
            uint256 amount,
            address signer,
            uint256 expiry,
            bytes memory signature
        )
    {
        //////////////////////// Message offsets //////////////////////////
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
    }

    /// @return recipient is the user when will be minted an EigenAgent
    function decodeMintEigenAgent(bytes memory message)
        public
        pure
        returns (address recipient)
    {
        //////////////////////// Message offsets //////////////////////////
        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 00000000000000000000000000000000000000000000000000000000000000e5 [64] string length
        // 0xcc15a557                                                       [96] function selector
        // 000000000000000000000000ff56509f4a1992c52577408cd2075b8a8531dc0a [100] recipient to mint to
        // 1c000000000000000000000000000000000000000000000000000000
        assembly {
            recipient := mload(add(message, 100))
        }
    }

    /*
     *
     *
     *                   Queue Withdrawals
     *
     *
    */

    /**
     * @param message CCIP message to Eigenlayer
     * @return arrayQueuedWithdrawalParams is the message sent to Eigenlayer when calling queueWithdrawals()
     * @return signer Owner of the EigenAgent
     * @return expiry Expiry of the signature (does not revert)
     * @return signature Signed by the user for their EigenAgent to excecute.
     */
    function decodeQueueWithdrawalsMsg(bytes memory message)
        public
        pure
        returns (
            IDelegationManager.QueuedWithdrawalParams[] memory arrayQueuedWithdrawalParams,
            address signer,
            uint256 expiry,
            bytes memory signature
        )
    {
        /// @dev note: Need to account for bytes message including arrays of QueuedWithdrawalParams
        /// We will need to check array length in SenderCCIP to determine gas as well.

        //////////////////////// Message offsets //////////////////////////
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
        private
        pure
        returns (IDelegationManager.QueuedWithdrawalParams memory)
    {
        /// @Note: expect to use this in a for-loop with i iteration variable
        //
        // Function Selector signature:
        //     bytes4(keccak256("queueWithdrawals((address[],uint256[],address)[])")),
        // Params:
        //     IDelegationManager.QueuedWithdrawalParams({
        //         strategies: strategiesToWithdraw,
        //         shares: sharesToWithdraw,
        //         withdrawer: withdrawer
        //     });

        // Example with 2 elements in QueuedWithdrawalParams[]
        //////////////////////// Message offsets //////////////////////////
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

    /**
     * @param message CCIP message to Eigenlayer
     * @return withdrawal is the message sent to Eigenlayer to call completeWithdrawal()
     * @return tokensToWithdraw Eigenlayer parameter when calling completeWithdrawal()
     * @return middlewareTimesIndex Eigenlayer parameter, used for slashing later.
     * @return receiveAsTokens determines whether to redeposit into Eigenlayer or receive as tokens.
     * @return signer Owner of the EigenAgent
     * @return expiry Expiry of the signature (does not revert)
     * @return signature Signed by the user for their EigenAgent to excecute.
     */
    function decodeCompleteWithdrawalMsg(bytes memory message)
        public
        pure
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
        // Function Selector signature:
        //     bytes4(keccak256("queueWithdrawals((address[],uint256[],address)[])")),
        // Params:
        //     struct Withdrawal {
        //         address staker;
        //         address delegatedTo;
        //         address withdrawer;
        //         uint256 nonce;
        //         uint32 startBlock;
        //         IStrategy[] strategies;
        //         uint256[] shares;
        //     }
        //
        //////////////////////// Message offsets //////////////////////////
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

        // Note: assumes we are withdrawing 1 token, tokensToWithdraw.length == 1
        withdrawal = _decodeCompleteWithdrawalMsgPart1(message);

        (
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        ) = _decodeCompleteWithdrawalMsgPart2(message);

        (
            signer,
            expiry,
            signature
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, 644); // signature (signer) starts at 644
    }

    function _decodeCompleteWithdrawalMsgPart1(bytes memory message)
        private
        pure
        returns (IDelegationManager.Withdrawal memory)
    {
        /// @Note decodes the first half of the CompleteWithdrawalMsg as we run into
        /// a "stack too deep" error with more than 16 variables in the function.
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
        private pure
        returns (
            IERC20[] memory tokensToWithdraw,
            uint256 middlewareTimesIndex,
            bool receiveAsTokens
        )
    {
        /// @Note decodes the second half of the CompleteWithdrawalMsg to avoid
        /// a "stack to deep" error with too many variables in the function.

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

        tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = IERC20(tokensToWithdraw0);

        return (
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );
    }


    /**
     * @dev This message is dispatched from L1 to L2 by ReceiverCCIP.sol
     * When sending a completeWithdrawal message, we first commit to a withdrawalTransferRoot on L2
     * so that when completeWithdrawal finishes on L1 and bridge the funds back to L2, the bridge knows
     * who the original owner associated with that withdrawalTransferRoot is.
     * @param message CCIP message to Eigenlayer
     * @return transferToAgentOwnerMsg contains the withdrawalTransferRoot which is sent back to L2
     */
    function decodeTransferToAgentOwnerMsg(bytes memory message)
        public pure
        returns (TransferToAgentOwnerMsg memory transferToAgentOwnerMsg)
    {
        //////////////////////// Message offsets //////////////////////////
        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000064 [64]
        // d8a85b48                                                         [96] function selector
        // dd900ac4d233ec9d74ac5af4ce89f87c78781d8fd9ee2aad62d312bdfdf78a14 [100] withdrawal root
        // 00000000000000000000000000000000000000000000000000000000

        bytes4 functionSelector;
        bytes32 withdrawalTransferRoot;

        assembly {
            functionSelector := mload(add(message, 96))
            withdrawalTransferRoot := mload(add(message, 100))
        }

        return TransferToAgentOwnerMsg({
            withdrawalTransferRoot: withdrawalTransferRoot
        });
    }

    /**
     * @param message CCIP message to Eigenlayer
     * @return claim The RewardsMerkleClaim to be processed.
     * Contains the root index, earner, token leaves, and required proofs
     * @return recipient The address recipient that receives the ERC20 rewards
     * @return signer Owner of the EigenAgent
     * @return expiry Expiry of the signature
     * @return signature Signed by the user for their EigenAgent to excecute.
     */
    function decodeProcessClaimMsg(bytes memory message)
        public
        view
        returns (
            IRewardsCoordinator.RewardsMerkleClaim memory claim,
            address recipient,
            address signer,
            uint256 expiry,
            bytes memory signature
        )
    {
        //////////////////////// Message offsets //////////////////////////
        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 00000000000000000000000000000000000000000000000000000000000005a5 [64] string length
        // 3ccc861d                                                         [96] processClaim function selector
        // 0000000000000000000000000000000000000000000000000000000000000040 [100] [OFFSET_1] RewardsMerkleClaim offset (100+64 = 164)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [132] recipient
        // 0000000000000000000000000000000000000000000000000000000000000054 [164] rootIndex
        // 0000000000000000000000000000000000000000000000000000000000010252 [196] earnerIndex
        // 0000000000000000000000000000000000000000000000000000000000000100 [228] [OFFSET_2] earnerTreeProofOffset (164 + 256 = 420)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [260] earnerLeaf.earner
        // 899e3bde2c009bda46a51ecacd5b3f6df0af2833168cc21cac5f75e8c610ce0d [292] earnerLeaf.earnerTokenRoot
        // 0000000000000000000000000000000000000000000000000000000000000340 [324] [OFFSET_2] tokenIndices[] offset (164 + 832 = 996)
        // 00000000000000000000000000000000000000000000000000000000000003a0 [356] [OFFSET_2] tokenTreeProofs[] offset (164 + 928 = 1092)
        // 0000000000000000000000000000000000000000000000000000000000000480 [388] [OFFSET_2] tokenLeaves[] offset (164 + 1152 = 1316)
        // 0000000000000000000000000000000000000000000000000000000000000220 [420] earnerTreeProof length (544 = 17 lines)
        // 32c3756cc20bcbdb7f8b25dcb3b904ea271776626d79cf1797932298c3bc5c62 [452] earnerTreeProof line 1
        // 8a09335bd33183649a1338e1ce19dcc11b6e7500659b71ddeb3680855b6eeffd [484]
        // d879bbbe67f12fc80b7df9df2966012d54b23b2c1265c708cc64b12d38acf88a [516]
        // 82277145d984d6a9dc5bdfa13cee09e543b810cef077330bd5828b746b8c92bb [548]
        // 622731e95bf8721578fa6c5e1ceaf2e023edb2b9c989c7106af8455ceae4aaad [580]
        // 1891758b2b17b58a3de5a98d61349658dd8b58bc3bfa5b08ec98ecf6bb45447b [612]
        // c45497275645c6cc432bf191633578079fc8787b0ee849e5af9c9a60375da395 [644]
        // a8f7fbb5bc80c876748e5e000aedc8de1e163bbb930f5f05f49eafdfe43407e1 [676]
        // daa8be3a9a68d8aeb17e55e562ae2d9efc90e3ced7e9992663a98c4309703e68 [708]
        // 728dfe1ec72d08c5516592581f81e8f2d8b703331bfd313ad2e343f9c7a35488 [740]
        // 21ed079b6f019319b2f7c82937cb24e1a2fde130b23d72b7451a152f71e8576a [772]
        // bddb9b0b135ad963dba00860e04a76e8930a74a5513734e50c724b5bd550aa3f [804]
        // 06e9d61d236796e70e35026ab17007b95d82293a2aecb1f77af8ee6b448abddb [836]
        // 2ddce73dbc52aab08791998257aa5e0736d60e8f2d7ae5b50ef48971836435fd [868]
        // 81a8556e13ffad0889903995260194d5330f98205b61e5c6555d8404f97d9fba [900]
        // 8c1b83ea7669c5df034056ce24efba683a1303a3a0596997fa29a5028c5c2c39 [932]
        // d6e9f04e75babdc9087f61891173e05d73f05da01c36d28e73c3b5594b61c107 [964]  earnerTreeProof line 17
        // 0000000000000000000000000000000000000000000000000000000000000002 [996]  tokenIndices[] length: 2
        // 0000000000000000000000000000000000000000000000000000000000000000 [1028] tokenIndices[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [1060] tokenIndices[1] value
        // 0000000000000000000000000000000000000000000000000000000000000002 [1092] tokenTreeProofs[] length: 2
        // 0000000000000000000000000000000000000000000000000000000000000040 [1124] [OFFSET_3] tokenTreeProofs[0] offset (1124 + 64 = 1188)
        // 0000000000000000000000000000000000000000000000000000000000000080 [1156] [OFFSET_3] tokenTreeProofs[1] offset (1124 + 128 = 1252)
        // 0000000000000000000000000000000000000000000000000000000000000020 [1188] tokenTreeProofs[0] length
        // 30c06778aea3c632bc61f3a0ffa0b57bd9ce9c2cf76f9ad2369f1b46081bc90b [1220] tokenTreeProofs[0] value
        // 0000000000000000000000000000000000000000000000000000000000000020 [1252] tokenTreeProofs[1] length
        // c82aa805d0910fc0a12610e7b59a440050529cf2a5b9e5478642bfa7f785fc79 [1284] tokenTreeProofs[1] value
        // 0000000000000000000000000000000000000000000000000000000000000002 [1316] tokenLeaves[] length: 2
        // 0000000000000000000000004bd30daf919a3f74ec57f0557716bcc660251ec0 [1348] tokenLeaves[0].token
        // 0000000000000000000000000000000000000000000000d47bfc8f6569c68ff4 [1380] tokenLeaves[0].cumulativeEarnings
        // 000000000000000000000000deeeee2b48c121e6728ed95c860e296177849932 [1412] tokenLeaves[1].token
        // 00000000000000000000000000000000000000000000be0b981f6fde72408340 [1444] tokenLeaves[1].cumulativeEarnings
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [1476] [OFFSET_4] signer
        // 0000000000000000000000000000000000000000000000000000000000015195 [1508] expiry
        // 03814b471f1beef18326b0d63c4a0f4431fdb72be167ee8aeb6212c8bd14d8e5 [1540] signature r
        // 74fa9f4f34373bef152fdcba912a10b0a5c77be53c00d04c4c6c77ae407136e7 [1572] signature s
        // 1b000000000000000000000000000000000000000000000000000000         [1604] signature v

        uint32 rootIndex;
        uint32 earnerIndex;
        uint32[] memory tokenIndices;
        bytes[] memory tokenTreeProofs;
        IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves;

        uint32 tokenLeavesOffset;
        {
            uint32 tokenIndicesOffset;
            uint32 tokenTreeProofsOffset;
            assembly {
                // These are always at these positions/offsets
                recipient := mload(add(message, 132))
                rootIndex := mload(add(message, 164))
                earnerIndex := mload(add(message, 196))
                // RewardsMerkleClaim struct fields start at 164, add 164
                tokenIndicesOffset := add(mload(add(message, 324)), 164)
                tokenTreeProofsOffset := add(mload(add(message, 356)), 164)
                tokenLeavesOffset := add(mload(add(message, 388)), 164)
            }

            (tokenIndices, tokenTreeProofs, tokenLeaves) = _decodeProcessClaimMsg_Part1(
                message,
                tokenIndicesOffset,
                tokenTreeProofsOffset,
                tokenLeavesOffset
            );
        }

        claim = IRewardsCoordinator.RewardsMerkleClaim({
            rootIndex: rootIndex,
            earnerIndex: earnerIndex,
            earnerTreeProof: _decodeProcessClaimMsg_Part2(message),
            earnerLeaf: _decodeProcessClaimMsg_Part3(message),
            tokenIndices: tokenIndices,
            tokenTreeProofs: tokenTreeProofs,
            tokenLeaves: tokenLeaves
        });

        uint32 tokenLeavesLength;
        assembly {
            tokenLeavesLength := mload(add(message, tokenLeavesOffset))
        }
        // sig offset is tokenLeaves length position + 1 line + tokenLeavesLength*2 lines.
        uint256 sigOffset = tokenLeavesOffset + 32 + (tokenLeavesLength * 64);

        (
            signer,
            expiry,
            signature
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, sigOffset);

        return (
            claim,
            recipient,
            signer,
            expiry,
            signature
        );
    }

    function _decodeProcessClaimMsg_Part1(
        bytes memory message,
        uint32 tokenIndicesOffset,
        uint32 tokenTreeProofsOffset,
        uint32 tokenLeavesOffset
    ) private pure returns (
        uint32[] memory tokenIndices,
        bytes[] memory tokenTreeProofs,
        IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves
    ) {

        uint32 tokenIndicesLength;
        uint32 tokenTreeProofsLength;
        uint32 tokenLeavesLength;

        assembly {
            tokenIndicesLength := mload(add(message, tokenIndicesOffset))
            tokenTreeProofsLength := mload(add(message, tokenTreeProofsOffset))
            tokenLeavesLength := mload(add(message, tokenLeavesOffset))
        }

        tokenIndices = new uint32[](tokenIndicesLength);
        tokenTreeProofs = new bytes[](tokenTreeProofsLength);
        tokenLeaves = new IRewardsCoordinator.TokenTreeMerkleLeaf[](tokenLeavesLength);

        {
            for (uint32 i = 0; i < tokenIndicesLength; ++i) {
                uint32 _tokenIndex;
                // add +1 line to skip array length, then i*32 for each following element
                uint32 _offset_elem = tokenIndicesOffset + 32 + i*32;
                assembly {
                    _tokenIndex := mload(add(message, _offset_elem))
                }
                tokenIndices[i] = _tokenIndex;
            }
        }
        {
            for (uint32 i = 0; i < tokenTreeProofsLength; ++i) {
                // tokenTreeProofs[bytes_proof, bytes_proof] is an array of bytes.
                uint32 _offset = tokenTreeProofsOffset + (tokenTreeProofsLength * 32) + (64 + i*64);
                // offset by length of tokenTreeProofs[] + 2 lines offset for each bytes_proof (length and value)
                tokenTreeProofs[i] = abi.encodePacked(_getTokenTreeProof(
                    message,
                    _offset,
                    tokenTreeProofsOffset,
                    tokenTreeProofsLength
                ));
            }
        }
        {
            for (uint32 i = 0; i < tokenLeavesLength; ++i) {
                address _tokenLeafToken;
                uint256 _cumulativeEarnings;
                uint32 _offset0 = 32 + i*64; // +1 line for array length
                uint32 _offset1 = 64 + i*64; // +2 lines for array length + token value
                // then add i*2 lines for each successive element.
                assembly {
                    _tokenLeafToken := mload(add(message, add(tokenLeavesOffset, _offset0)))
                    _cumulativeEarnings := mload(add(message, add(tokenLeavesOffset, _offset1)))
                }
                tokenLeaves[i] = IRewardsCoordinator.TokenTreeMerkleLeaf({
                    token: IERC20(_tokenLeafToken),
                    cumulativeEarnings: _cumulativeEarnings
                });
            }
        }

        return (
            tokenIndices,
            tokenTreeProofs,
            tokenLeaves
        );
    }

    function _getTokenTreeProof(
        bytes memory message,
        uint32 offset,
        uint32 tokenTreeProofsOffset,
        uint32 tokenTreeProofsLength
    ) private pure returns (bytes32[] memory) {

        uint32 lengthProof;
        assembly {
            lengthProof := mload(add(message, sub(offset, 32))) // 1 line before offset
        }

        require(lengthProof % 32 == 0, "tokenTreeProof length must be a multiple of 32");

        lengthProof = lengthProof / 32;
        bytes32[] memory tokenTreeProofArray = new bytes32[](lengthProof);

        for (uint32 k = 0; k < lengthProof; ++k) {
            bytes32 _proofLine;
            assembly {
                _proofLine := mload(add(message, add(offset, mul(k, 32))))
            }
            tokenTreeProofArray[k] = _proofLine;
        }

        return tokenTreeProofArray;
    }

    function _decodeProcessClaimMsg_Part2(bytes memory message)
        public
        pure
        returns (bytes memory)
    {
        uint32 earnerTreeProofOffset;
        uint32 earnerTreeProofLength;

        assembly {
            // earnerTreeProofOffset is always at position 228.
            // RewardsMerkleClaim struct fields start at 164
            earnerTreeProofOffset := add(mload(add(message, 228)), 164)
            earnerTreeProofLength := mload(add(message, earnerTreeProofOffset)) // 544
        }

        require(earnerTreeProofLength % 32 == 0, "earnerTreeProofLength must be divisible by 32");

        uint32 earnerTreeProofLines = earnerTreeProofLength / 32; // 544/32 = 17 lines
        bytes32[] memory earnerTreeProofArray = new bytes32[](earnerTreeProofLines);

        for (uint32 i = 0; i < earnerTreeProofLines; ++i) {
            bytes32 proofChunk;
            assembly {
                proofChunk := mload(add(
                    add(message, add(earnerTreeProofOffset, 32)), // first 32bytes is length, proof starts after
                    mul(i, 32) // increment by 32-byte lines
                ))
            }
            // console.logBytes32(proofChunk);
            earnerTreeProofArray[i] = proofChunk;
        }

        bytes memory earnerTreeProof = abi.encodePacked(earnerTreeProofArray);
        return earnerTreeProof;
    }

    function _decodeProcessClaimMsg_Part3(bytes memory message)
        private
        pure
        returns (
            IRewardsCoordinator.EarnerTreeMerkleLeaf memory earnerLeaf
        )
    {
        address earner;
        bytes32 earnerTokenRoot;

        assembly {
            // EarnerLeaf.earner is always at position 260
            earner := mload(add(message, 260))
            // EarnerLeaf.earnerTokenRoot is always at position 292
            earnerTokenRoot := mload(add(message, 292))
        }

        earnerLeaf = IRewardsCoordinator.EarnerTreeMerkleLeaf({
            earner: earner,
            earnerTokenRoot: earnerTokenRoot
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

    /// @param message CCIP message to Eigenlayer
    /// @return operator Eigenalyer parameter: address to delegate to.
    /// @return approverSignatureAndExpiry Eigenlayer parameter: signature from Operator.
    /// @return approverSalt Eigenlayer parameter: approver salt.
    /// @return signer owner of the EigenAgent
    /// @return expiryEigenAgent expiry of the signature (does not revert)
    /// @return signatureEigenAgent Signed by the user for their EigenAgent to excecute.
    function decodeDelegateToMsg(bytes memory message)
        public
        pure
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
        //
        //////////////////////// Message offsets //////////////////////////
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

    /**
     * @param message CCIP message to Eigenlayer
     * @return staker address of the EigenAgent (the staker from Eigenlayer's perspective)
     * @return signer Owner of the EigenAgent
     * @return expiry Expiry of the signature
     * @return signature Signed by the user for their EigenAgent to excecute.
     */
    function decodeUndelegateMsg(bytes memory message)
        public
        pure
        returns (
            address staker, // eigenAgent
            address signer,
            uint256 expiry,
            bytes memory signature
        )
    {
        //////////////////////// Message offsets //////////////////////////
        // 0000000000000000000000000000000000000000000000000000000000000020
        // 00000000000000000000000000000000000000000000000000000000000000a5
        // da8be864                                                         [96] function selector
        // 0000000000000000000000002fd5589daa0eb790b9237a300479924f9023efef [100] staker address (delegating)
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
            expiry,
            signature
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, 132);

        return (
            staker,
            signer,
            expiry,
            signature
        );
    }

}