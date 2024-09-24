//SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {ISignatureUtils} from "@eigenlayer-contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";



struct TransferToAgentOwnerMsg {
    bytes32 transferRoot; // can be either a withdrawalTransferRoot or rewardTransferRoot
}

library AgentOwnerSignature {

    /**
     * @dev Decodes user signatures on all CCIP messages to EigenAgents
     * @param message is a CCIP message to Eigenlayer
     * @param sigOffset is the offset where the user signature begins
     */
    function decodeAgentOwnerSignature(bytes memory message, uint256 sigOffset) public pure returns (
        address signer,
        uint256 expiry,
        bytes memory signature
    ) {

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
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, message.length - 124);
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
        //////////////////////// Message offsets //////////////////////////
        // 0000000000000000000000000000000000000000000000000000000000000020 [32] string offset
        // 00000000000000000000000000000000000000000000000000000000000001a5 [64] string length
        // 0dd8dd02                                                         [96] function selector
        // 0000000000000000000000000000000000000000000000000000000000000020 [100] qwp[] array offset
        // 0000000000000000000000000000000000000000000000000000000000000001 [132] qwp[] array length
        // 0000000000000000000000000000000000000000000000000000000000000020 [164] qwp[0] struct offsets...
        // ...
        // ... QueuedWithdrawalParams structs
        // ...
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [-124] signer (message.length - 124)
        // 00000000000000000000000000000000000000000000000000000000424b2a0e [-92] expiry
        // 1f7c77a6b0940a7ce34edf2821d323701213db8e237c46fdf8b7bedc8f295359 [-60] signature r
        // 1b82b0bd80af2140d658af1312ba94049de6c699533bca58da0f29d659cdf61a [-28] signature s
        // 1c000000000000000000000000000000000000000000000000000000         [-29] signature v

        uint256 arrayLength;
        assembly {
            arrayLength := mload(add(message, 132))
        }

        require(arrayLength >= 1, "decodeQueueWithdrawalsMsg: arrayLength must be at least 1");

        arrayQueuedWithdrawalParams = new IDelegationManager.QueuedWithdrawalParams[](arrayLength);

        for (uint256 i; i < arrayLength; i++) {
            IDelegationManager.QueuedWithdrawalParams memory wp;
            wp = _decodeSingleQueueWithdrawalMsg(message, i);
            arrayQueuedWithdrawalParams[i] = wp;
        }

        uint256 sigOffset = message.length - 124;
        // signature starts 124 bytes back from the end of the message
        (
            signer,
            expiry,
            signature
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, sigOffset);
        return (
            arrayQueuedWithdrawalParams,
            signer,
            expiry,
            signature
        );
    }

    function _decodeSingleQueueWithdrawalMsg(bytes memory message, uint256 i)
        private
        pure
        returns (IDelegationManager.QueuedWithdrawalParams memory)
    {
        // Function Selector signature:
        //     bytes4(keccak256("queueWithdrawals((address[],uint256[],address)[])")),
        // Params:
        //     QueuedWithdrawalParams {
        //         Strategy[] strategies;
        //         uint256[] shares;
        //         address withdrawer;
        //     }

        // Example with 2 elements in QueuedWithdrawalParams[] with multiple strategies
        // QueuedWithdrawalParams[2] with strategies[2] and shares[2]
        //////////////////////// Message offsets //////////////////////////
        // 0000000000000000000000000000000000000000000000000000000000000020
        // 0000000000000000000000000000000000000000000000000000000000000405
        // 0dd8dd02
        // 0000000000000000000000000000000000000000000000000000000000000020 [100] array offset (100 + 32 = 132)
        // 0000000000000000000000000000000000000000000000000000000000000003 [132] struct[] length = 3
        // 0000000000000000000000000000000000000000000000000000000000000060 [164] struct[0] offset (164 + 96 = 260)
        // 0000000000000000000000000000000000000000000000000000000000000140 [196] struct[1] offset (164 + 320 = 484)
        // 0000000000000000000000000000000000000000000000000000000000000220 [228] struct[2] offset (164 + 544 = 708)
        // 0000000000000000000000000000000000000000000000000000000000000060 [260] struct[0].strategies[] offset (260 + 96 = 356)
        // 00000000000000000000000000000000000000000000000000000000000000a0 [292] struct[0].shares[] offset (260 + 160 = 420)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [324] struct[0].withdrawer (static value)
        // 0000000000000000000000000000000000000000000000000000000000000001 [356] struct[0].strategies[].length = 1
        // 000000000000000000000000b111111ad20e9d85d5152ae68f45f40a11111111 [388] struct[0].strategies[] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [420] struct[0].shares[].length = 1
        // 0000000000000000000000000000000000000000000000000023e2ce54e05000 [452] struct[0].shares[] value
        // 0000000000000000000000000000000000000000000000000000000000000060 [484] struct[1].strategies[] offset (484 + 96 = 580)
        // 00000000000000000000000000000000000000000000000000000000000000a0 [516] struct[1].shares[] offset (484 + 160 = 644)
        // 0000000000000000000000007e5f4552091a69125d5dfcb7b8c2659029395bdf [548] struct[1].withdrawer (static value)
        // 0000000000000000000000000000000000000000000000000000000000000001 [580] struct[1].strategies[].length = 1
        // 000000000000000000000000b222222ad20e9d85d5152ae68f45f40a22222222 [612] struct[1].strategies[] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [644] struct[1].shares[].length = 1
        // 0000000000000000000000000000000000000000000000000047c59ca9c0a000 [676] struct[1].shares[] value
        // 0000000000000000000000000000000000000000000000000000000000000060 [708] struct[2].strategies[] offset (708 + 96 = 804)
        // 00000000000000000000000000000000000000000000000000000000000000c0 [740] struct[2].shares[] offset (708 + 192 = 900)
        // 0000000000000000000000002b5ad5c4795c026514f8317c7a215e218dccd6cf [772] struct[2].withdrawer (static value)
        // 0000000000000000000000000000000000000000000000000000000000000002 [804] struct[2].strategies[].length = 2
        // 000000000000000000000000b333333ad20e9d85d5152ae68f45f40a33333333 [836] struct[2].strategies[0] value
        // 000000000000000000000000b444444ad20e9d85d5152ae68f45f40a44444444 [868] struct[2].strategies[1] value
        // 0000000000000000000000000000000000000000000000000000000000000002 [900] struct[2].shares[].length = 2
        // 000000000000000000000000000000000000000000000000008f8b3953814000 [932] struct[2].shares[0] value
        // 0000000000000000000000000000000000000000000000000000000000000000 [964] struct[2].shares[0] value
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [996] signer
        // 0000000000000000000000000000000000000000000000000000000000015195 [1028] expiry
        // 3b9af3af035e664cf70928cf3cff00e0dc7af51a75a6f3a99b7e76ec2254f775 [1060] sig r
        // 57946e51a5170e647f770b3f524fda096f67a1bf8c34db20d702bcd7af39ea6a [1092] sig s
        // 1b000000000000000000000000000000000000000000000000000000         [1120] sig v

        uint256 structOffset;
        uint256 strategiesOffset;
        uint256 sharesOffset;
        address withdrawer;

        uint256 strategiesLength;
        uint256 sharesLength;

        {
            uint256 baseOffset = 164;
            assembly {
                // i-th struct's offset
                structOffset := mload(add(add(message, baseOffset), mul(i, 0x20)))

                strategiesOffset := add(
                    add(baseOffset, structOffset),
                    mload(add(add(message, baseOffset), structOffset))
                )
                sharesOffset := add(
                    add(baseOffset, structOffset),
                    mload(add(add(add(message, baseOffset), structOffset), 0x20))
                )
                withdrawer := mload(add(add(add(message, baseOffset), structOffset), 0x40))

                strategiesLength := mload(add(message, strategiesOffset))
                sharesLength := mload(add(message, sharesOffset))
            }
        }

        IStrategy[] memory strategies = new IStrategy[](strategiesLength);
        {
            for (uint256 j = 0; j < strategiesLength; ++j) {
                address strategy;
                assembly {
                    // 292 + 32 (skip length) + (j*32) for strategy[j] value
                    strategy := mload(add(add(message, strategiesOffset), mul(add(1, j), 0x20)))
                }
                strategies[j] = IStrategy(strategy);
            }
        }

        uint256[] memory shares = new uint256[](sharesLength);
        {
            for (uint256 k = 0; k < sharesLength; ++k) {
                uint256 share;
                assembly {
                    // 388 + 32 (skip length) + (k*32) for share[k] value
                    share := mload(add(add(message, sharesOffset), mul(add(1, k), 0x20)))
                }
                shares[k] = share;
            }
        }

        return IDelegationManager.QueuedWithdrawalParams({
            strategies: strategies,
            shares: shares,
            withdrawer: withdrawer
        });
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
        //     cast sig "completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],uint256,bool)" == 0x60d7faed
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
        // 0000000000000000000000000000000000000000000000000000000000000305 [64]
        // 60d7faed                                                         [96]
        // 0000000000000000000000000000000000000000000000000000000000000080 [100] withdrawal struct offset (100 + 128 = 228)
        // 0000000000000000000000000000000000000000000000000000000000000220 [132] tokens[] offset (100 + 544 = 644)
        // 0000000000000000000000000000000000000000000000000000000000000000 [164] middlewareTimesIndex
        // 0000000000000000000000000000000000000000000000000000000000000001 [196] receiveAsTokens
        // 000000000000000000000000acf9a3539b856e752fe1568d12b501180ad53e78 [228] withdrawal.staker
        // 0000000000000000000000000000000000000000000000000000000000000000 [260] withdrawal.delegatedTo
        // 000000000000000000000000acf9a3539b856e752fe1568d12b501180ad53e78 [292] withdrawal.withdrawer
        // 0000000000000000000000000000000000000000000000000000000000000000 [324] withdrawal.nonce
        // 0000000000000000000000000000000000000000000000000000000000000001 [356] withdrawal.startBlock
        // 00000000000000000000000000000000000000000000000000000000000000e0 [388] withdrawal.strategies[] offset (228 + 224 = 452)
        // 0000000000000000000000000000000000000000000000000000000000000140 [420] withdrawal.shares[] offset (260 + 320 = 548)
        // 0000000000000000000000000000000000000000000000000000000000000002 [452] withdrawal.strategies[] length = 2
        // 00000000000000000000000041306849382357029ab3081fc1e02241f28aa9e0 [484] withdrawal.strategies[0] value
        // 00000000000000000000000082455de76aa228977e11247f05790a80576468ab [516] withdrawal.strategies[1] value
        // 0000000000000000000000000000000000000000000000000000000000000002 [548] withdrawal.shares[] length = 2
        // 000000000000000000000000000000000000000000000000016345785d8a0000 [580] withdrawal.shares[0] value
        // 000000000000000000000000000000000000000000000000016345785d8a0000 [612] withdrawal.shares[1] value
        // 0000000000000000000000000000000000000000000000000000000000000002 [644] tokens[] length = 2
        // 0000000000000000000000008fdfb0d901de9055c110569cdc08f54bd4af7128 [676] tokens[0] value
        // 000000000000000000000000a0cb889707d426a7a386870a03bc70d1b0697598 [708] tokens[1] value
        // 000000000000000000000000a6ab3a612722d5126b160eef5b337b8a04a76dd8 [740] signer
        // 0000000000000000000000000000000000000000000000000000000000000e11 [768] expiry
        // 65bd0ed9d964e9415ebc19303873f672eeb9b1709e957ce49b0224747fb92378 [800] sig r
        // 55ce98314bbe28891c925ff62cc66e35ed9cf11dc03b774813aafa2eec0dedd2 [832] sig s
        // 1c000000000000000000000000000000000000000000000000000000         [864] sig v

        // withdrawal struct always starts on offset 228
        withdrawal = _decodeCompleteWithdrawalMsgPart1(message, 228);

        (
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        ) = _decodeCompleteWithdrawalMsgPart2(message);

        uint256 sigOffset = message.length - 124;
        // signature starts 124 bytes back from the end of the message
        (
            signer,
            expiry,
            signature
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, sigOffset);
    }

    function _decodeCompleteWithdrawalMsgPart1(bytes memory message, uint256 woffset)
        internal
        pure
        returns (IDelegationManager.Withdrawal memory withdrawal)
    {
        /// Decodes the first half of the CompleteWithdrawalMsg as we run into
        /// a "stack too deep" error with more than 16 variables in the function.
        {
            address staker;
            address delegatedTo;
            address withdrawer;
            uint256 nonce;
            uint32 startBlock;
            assembly {
                staker := mload(add(message, woffset))
                delegatedTo := mload(add(add(message, woffset), 0x20))
                withdrawer := mload(add(add(message, woffset), 0x40))
                nonce := mload(add(add(message, woffset), 0x60))
                startBlock := mload(add(add(message, woffset), 0x80))
            }
            withdrawal.staker = staker;
            withdrawal.delegatedTo = delegatedTo;
            withdrawal.withdrawer = withdrawer;
            withdrawal.nonce = nonce;
            withdrawal.startBlock = startBlock;
        }

        {
            uint256 strategies_offset;
            uint256 shares_offset;
            uint256 strategies_length;
            uint256 shares_length;

            assembly {
                strategies_offset := mload(add(add(message, woffset), 0xa0))
                shares_offset := mload(add(add(message, woffset), 0xc0))
                strategies_length := mload(add(add(message, woffset), strategies_offset))
                shares_length := mload(add(add(message, woffset), shares_offset))
            }

            IStrategy[] memory strategies = new IStrategy[](strategies_length);
            uint256[] memory shares = new uint256[](shares_length);

            for (uint256 i = 0; i < strategies.length; ++i) {
                address strategy;
                assembly {
                    strategy := mload(add(add(add(message, woffset), strategies_offset), mul(add(1, i), 0x20)))
                }
                strategies[i] = IStrategy(strategy);
            }

            for (uint256 j = 0; j < shares.length; ++j) {
                uint256 share;
                assembly {
                    share := mload(add(add(add(message, woffset), shares_offset), mul(add(1, j), 0x20)))
                }
                shares[j] = share;
            }

            withdrawal.strategies = strategies;
            withdrawal.shares = shares;
        }
    }

    function _decodeCompleteWithdrawalMsgPart2(bytes memory message)
        private pure
        returns (
            IERC20[] memory tokensToWithdraw,
            uint256 middlewareTimesIndex,
            bool receiveAsTokens
        )
    {
        uint256 basePosition = 100;
        uint256 tokensOffset;
        uint256 tokensLength;

        assembly {
            tokensOffset := mload(add(add(message, basePosition), 0x20)) // 1 line after withdrawal offset
            middlewareTimesIndex := mload(add(message, 164))
            receiveAsTokens := mload(add(message, 196))
            // 100 + 544 = 644
            tokensLength := mload(add(add(message, basePosition), tokensOffset))
        }

        tokensToWithdraw = new IERC20[](tokensLength);
        for (uint256 i = 0; i < tokensToWithdraw.length; ++i) {
            address token;
            assembly {
                // 100 + 544 + (1 + i)*0x20 for i-th token
                token := mload(add(add(add(message, basePosition), tokensOffset), mul(add(1, i), 0x20)))
            }
            tokensToWithdraw[i] = IERC20(token);
        }

        return (
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );
    }

    /**
     * @dev This message is dispatched from L1 to L2 by ReceiverCCIP.sol
     * For Withdrawals: When sending a completeWithdrawal message, we first commit to a withdrawalTransferRoot
     * on L2 so that when completeWithdrawal finishes on L1 and bridge the funds back to L2, the bridge knows
     * who the original owner associated with that withdrawalTransferRoot is.
     * For Rewards processClaims: we commit a rewardTransferRoot in the same way.
     * @param message CCIP message to Eigenlayer
     * @return transferToAgentOwnerMsg contains the transferRoot which is sent back to L2
     */
    function decodeTransferToAgentOwnerMsg(bytes memory message)
        public pure
        returns (TransferToAgentOwnerMsg memory transferToAgentOwnerMsg)
    {
        //////////////////////// Message offsets //////////////////////////
        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000064 [64]
        // d8a85b48                                                         [96] function selector
        // dd900ac4d233ec9d74ac5af4ce89f87c78781d8fd9ee2aad62d312bdfdf78a14 [100] transferRoot
        // 00000000000000000000000000000000000000000000000000000000

        bytes4 functionSelector;
        bytes32 transferRoot;

        assembly {
            functionSelector := mload(add(message, 96))
            transferRoot := mload(add(message, 100))
        }

        return TransferToAgentOwnerMsg({
            transferRoot: transferRoot
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
        pure
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
        // 1b000000000000000000000000000000000000000000000000000000         [1600] signature v

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
                // These parameters are always at these positions/offsets
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

        uint256 sigOffset = message.length - 124;
        // signature starts 124 bytes back from the end of the message
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
                // tokenTreeProofs = bytes[] is an array of dynamic length bytestrings.
                // each bytes_proof is a dynamic length element, so it has a length, and value.
                // So we need the lengths and offsets for each byte_proof element:
                uint32 _elemLinesOffset = tokenTreeProofsOffset + 32 + (i*32);
                uint32 _elemOffset;
                assembly {
                    _elemOffset := mload(add(message, _elemLinesOffset))
                }
                // offset by length of tokenTreeProofs[] + 2 lines offset for each bytes_proof (length and value)
                tokenTreeProofs[i] = _getTokenTreeProof(
                    message,
                    _elemOffset, // each i-th element's offset
                    tokenTreeProofsOffset // root offset of tokenTreeProofs
                );
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
        uint32 elemOffset,
        uint32 tokenTreeProofsOffset
    ) private pure returns (bytes memory) {

        uint32 elemLengthOffset = elemOffset + 32; // byteproofs element lengths begin on next line
        uint32 elemValueOffset = elemOffset + 64; // byteproofs element values begin 2 lines after

        uint32 lengthOfProof;
        assembly {
            lengthOfProof := mload(add(message, add(tokenTreeProofsOffset, elemLengthOffset)))
        }

        require(lengthOfProof % 32 == 0, "tokenTreeProof length must be a multiple of 32");
        // allocate memory for proof (32 bytes for length + lengthOfProof bytes)
        bytes memory tokenTreeProof = new bytes(lengthOfProof);

        assembly {
            // mcopy is only available in solc ^0.8.24
            mcopy(
                // shift 32 bytes past byte array length, copy proof value here
                add(tokenTreeProof, 0x20),
                // memory location of tokenTreeProof value
                add(message, add(tokenTreeProofsOffset, elemValueOffset)),
                // length of tokenTreeProof in bytes
                lengthOfProof
            )
        }

        return tokenTreeProof;

        //// Alternatively if using solc < 0.8.24
        // uint32 numLines = lengthOfProof / 32;
        // bytes32[] memory tokenTreeProofArray = new bytes32[](numLines);
        // // iterate through each line of each i-th byteproof and join the byteproofs
        // for (uint32 j = 0; j < numLines; ++j) {
        //     bytes32 _proofLine;
        //     uint32 _elemValueOffset = elemValueOffset + j*32;
        //     assembly {
        //         _proofLine := mload(add(message, add(tokenTreeProofsOffset, _elemValueOffset)))
        //     }
        //     tokenTreeProofArray[j] = _proofLine;
        // }
        // return abi.encodePacked(tokenTreeProofArray);
    }

    function _decodeProcessClaimMsg_Part2(bytes memory message)
        private
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
        // allocate memory for proof (32 bytes for length + lengthOfProof bytes)
        bytes memory earnerTreeProof = new bytes(earnerTreeProofLength);

        assembly {
            // mcopy is only available in solc ^0.8.24
            mcopy(
                // shift 32 bytes past byte array length, copy proof value here
                add(earnerTreeProof, 0x20),
                // first 32bytes is length, proof starts after so add 0x20
                add(message, add(earnerTreeProofOffset, 0x20)),
                // length of earnerTreeProof in bytes
                earnerTreeProofLength
            )
        }

        return earnerTreeProof;

        //// Alternatively if using solc < 0.8.24
        // uint32 earnerTreeProofLines = earnerTreeProofLength / 32; // 544/32 = 17 lines
        // bytes32[] memory earnerTreeProofArray = new bytes32[](earnerTreeProofLines);
        //
        // for (uint32 i = 0; i < earnerTreeProofLines; ++i) {
        //     bytes32 proofChunk;
        //     assembly {
        //         proofChunk := mload(add(
        //             add(message, add(earnerTreeProofOffset, 32)), // first 32bytes is length, proof starts after
        //             mul(i, 32) // increment by 32-byte lines
        //         ))
        //     }
        //     earnerTreeProofArray[i] = proofChunk;
        // }
        // return abi.encodePacked(earnerTreeProofArray);
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
 *                   Complate Withdrawals (Array version)
 *
 *
 */

library CompleteWithdrawalsArrayDecoder {

    function decodeCompleteWithdrawalsMsg(bytes memory message)
        public
        pure
        returns (
            IDelegationManager.Withdrawal[] memory withdrawals,
            IERC20[][] memory tokens,
            uint256[] memory middlewareTimesIndexes,
            bool[] memory receiveAsTokens,
            address signer,
            uint256 expiry,
            bytes memory signature
        )
    {
        // Function Selector signature:
        //     cast sig "completeQueuedWithdrawals((address,address,address,uint256,uint32,address[],uint256[])[],address[][],uint256[],bool[])" == 0x33404396
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
        // 0000000000000000000000000000000000000000000000000000000000000020
        // 00000000000000000000000000000000000000000000000000000000000005c5
        // 33404396
        // 0000000000000000000000000000000000000000000000000000000000000080 [100] withdrawals[] offset (100 + 128 = 228)[4 lines]
        // 00000000000000000000000000000000000000000000000000000000000003a0 [132] tokens[][] offset (100 + 928 = 1028)[29 lines]
        // 0000000000000000000000000000000000000000000000000000000000000480 [164] middlewareTimesIndexes[] offset (100 + 1152 = 1252)
        // 00000000000000000000000000000000000000000000000000000000000004e0 [196] receiveAsTokens[] offset (100 + 1248 = 1348)
        // 0000000000000000000000000000000000000000000000000000000000000002 [228] withdrawals[] length = 2
        // 0000000000000000000000000000000000000000000000000000000000000040 [260] withdrawals[0] struct offset (260 + 64 = 324)
        // 00000000000000000000000000000000000000000000000000000000000001a0 [292] withdrawals[1] struct offset (260 + 416 = 676)
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [324] withdrawals[0].staker
        // 0000000000000000000000000000000000000000000000000000000000000000 [356] withdrawals[0].delegatedTo
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [388] withdrawals[0].withdrawer
        // 0000000000000000000000000000000000000000000000000000000000000000 [420] withdrawals[0].nonce
        // 0000000000000000000000000000000000000000000000000000000000000001 [452] withdrawals[0].startBlock
        // 00000000000000000000000000000000000000000000000000000000000000e0 [484] withdrawals[0].strategies offset (324 + 224 = 548)
        // 0000000000000000000000000000000000000000000000000000000000000120 [516] withdrawals[0].shares offset (324 + 288 = 612)
        // 0000000000000000000000000000000000000000000000000000000000000001 [548] withdrawals[0].strategies length
        // 00000000000000000000000041306849382357029ab3081fc1e02241f28aa9e0 [580] withdrawals[0].strategies[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [612] withdrawals[0].shares length
        // 000000000000000000000000000000000000000000000000000b677a5dbaa000 [644] withdrawals[0].shares[0] value
        // 000000000000000000000000a6Ab3a612722D5126b160eEf5B337B8A04A76Dd8 [676] withdrawals[1].staker
        // 0000000000000000000000000000000000000000000000000000000000000000 [708] withdrawals[1].delegatedTo
        // 000000000000000000000000a6Ab3a612722D5126b160eEf5B337B8A04A76Dd8 [740] withdrawals[1].withdrawer
        // 0000000000000000000000000000000000000000000000000000000000000001 [772] withdrawals[1].nonce
        // 0000000000000000000000000000000000000000000000000000000000000001 [804] withdrawals[1].startBlock
        // 00000000000000000000000000000000000000000000000000000000000000e0 [836] withdrawals[1].strategies offset (676 + 224 = 900)
        // 0000000000000000000000000000000000000000000000000000000000000120 [868] withdrawals[1].shares offset (676 + 288 = 964)
        // 0000000000000000000000000000000000000000000000000000000000000001 [900] withdrawals[1].strategies length = 1
        // 00000000000000000000000041306849382357029ab3081fc1e02241f28aa9e0 [932] withdrawals[1].strategies[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [964] withdrawals[1].shares length = 1
        // 000000000000000000000000000000000000000000000000000b677a5dbaa000 [996] withdrawals[1].shares[0] value
        // 0000000000000000000000000000000000000000000000000000000000000002 [1028] tokens[][] length = 2
        // 0000000000000000000000000000000000000000000000000000000000000040 [1060] tokens[0][] offset (1060 + 64 = 1124)
        // 00000000000000000000000000000000000000000000000000000000000000a0 [1092] tokens[1][] offset (1060 + 160 = 1220)
        // 0000000000000000000000000000000000000000000000000000000000000002 [1124] tokens[0][] length = 2
        // 0000000000000000000000000000000000000000000000000000000000000006 [1156] tokens[0][0] value
        // 0000000000000000000000000000000000000000000000000000000000000007 [1188] tokens[0][1] value
        // 0000000000000000000000000000000000000000000000000000000000000003 [1220] tokens[1][] length = 3
        // 0000000000000000000000000000000000000000000000000000000000000008 [1252] tokens[1][0] value
        // 0000000000000000000000000000000000000000000000000000000000000009 [1284] tokens[1][1] value
        // 0000000000000000000000000000000000000000000000000000000000000005 [1316] tokens[1][2] value
        // 0000000000000000000000000000000000000000000000000000000000000002 [1348] middlewareSharesIndexes[] length = 2
        // 0000000000000000000000000000000000000000000000000000000000000000 [1380] middlewareSharesIndexes[0] value
        // 0000000000000000000000000000000000000000000000000000000000000001 [1412] middlewareSharesIndexes[1] value
        // 0000000000000000000000000000000000000000000000000000000000000002 [1444] receiveAsTokens[] length = 2
        // 0000000000000000000000000000000000000000000000000000000000000001 [1476] receiveAsTokens[0] value
        // 0000000000000000000000000000000000000000000000000000000000000000 [1508] receiveAsTokens[1] value
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [1540] signer
        // 0000000000000000000000000000000000000000000000000000000000015195 [1572] expiry
        // d75fd557096ca23f683d964df7fdfce79f3295c8e19a4da4811beab582eaa95a [1604] sig r
        // 3891eaf0232a18a5ba93cc0aa801e966be7427f249c4d3c07727dfc4d29971e8 [1636] sig s
        // 1c000000000000000000000000000000000000000000000000000000         [1664] sig v

        // withdrawals
        {
            uint256 withdrawals_length;
            assembly {
                withdrawals_length := mload(add(message, 0xe4)) // [byte location: 228]
            }

            withdrawals = new IDelegationManager.Withdrawal[](withdrawals_length);

            for (uint256 i = 0; i < withdrawals_length; ++i) {
                // for each element in withdrawals[] array
                uint256 withdrawal_elem_offset;
                uint256 j = i + 1;
                assembly {
                    withdrawal_elem_offset := mload(add(add(message, 0xe4), mul(j, 0x20)))
                }
                withdrawal_elem_offset += 260; // offset_1 = 260
                withdrawals[i] = _decodeCompleteWithdrawalsMsg_A(message, withdrawal_elem_offset);
            }
        }

        // tokens
        {
            uint256 tokensOffset;
            uint256 tokensLength;
            assembly {
                tokensOffset := mload(add(message, 132))
                tokensLength := mload(add(add(message, 100), tokensOffset))
            }
            tokens = _decodeCompleteWithdrawalsMsg_B(message, 100+tokensOffset, tokensLength);
        }

        // middlewareTimesIndexes
        {
            uint256 middlewareOffset;
            assembly {
                middlewareOffset := mload(add(message, 164))
            }
            middlewareTimesIndexes = _decodeCompleteWithdrawalsMsg_C(message, 100+middlewareOffset);
        }

        // receiveAsTokens
        uint256 receiveAsTokensOffset;
        uint256 receiveAsTokensLength;
        {
            assembly {
                receiveAsTokensOffset := mload(add(message, 196))
                receiveAsTokensLength := mload(add(add(message, 100), receiveAsTokensOffset))
            }
            receiveAsTokens = _decodeCompleteWithdrawalsMsg_D(message, 100+receiveAsTokensOffset);
        }

        uint256 sigOffset = message.length - 124;
        // signature starts 124 bytes back from the end of the message
        (
            signer,
            expiry,
            signature
        ) = AgentOwnerSignature.decodeAgentOwnerSignature(message, sigOffset);
    }

    function _decodeCompleteWithdrawalsMsg_A(bytes memory message, uint256 woffset)
        private
        pure
        returns (IDelegationManager.Withdrawal memory withdrawal)
    {
        {
            address staker;
            address delegatedTo;
            address withdrawer;
            uint256 nonce;
            uint32 startBlock;
            assembly {
                staker := mload(add(message, woffset))
                delegatedTo := mload(add(add(message, woffset), 0x20))
                withdrawer := mload(add(add(message, woffset), 0x40))
                nonce := mload(add(add(message, woffset), 0x60))
                startBlock := mload(add(add(message, woffset), 0x80))
            }
            withdrawal.staker = staker;
            withdrawal.delegatedTo = delegatedTo;
            withdrawal.withdrawer = withdrawer;
            withdrawal.nonce = nonce;
            withdrawal.startBlock = startBlock;
        }

        {
            uint256 strategies_offset;
            uint256 shares_offset;
            uint256 strategies_length;
            uint256 shares_length;

            assembly {
                strategies_offset := mload(add(add(message, woffset), 0xa0))
                shares_offset := mload(add(add(message, woffset), 0xc0))
                strategies_length := mload(add(add(message, woffset), strategies_offset))
                shares_length := mload(add(add(message, woffset), shares_offset))
            }

            IStrategy[] memory strategies = new IStrategy[](strategies_length);
            uint256[] memory shares = new uint256[](shares_length);

            for (uint256 i = 0; i < strategies.length; ++i) {
                address strategy;
                assembly {
                    strategy := mload(add(add(add(message, woffset), strategies_offset), mul(add(1, i), 0x20)))
                }
                strategies[i] = IStrategy(strategy);
            }

            for (uint256 j = 0; j < shares.length; ++j) {
                uint256 share;
                assembly {
                    share := mload(add(add(add(message, woffset), shares_offset), mul(add(1, j), 0x20)))
                }
                shares[j] = share;
            }

            withdrawal.strategies = strategies;
            withdrawal.shares = shares;
        }
    }

    function _decodeCompleteWithdrawalsMsg_B(bytes memory message, uint256 offset, uint256 tokensLength)
        private
        pure
        returns (IERC20[][] memory tokens)
    {
        tokens = new IERC20[][](tokensLength);

        for (uint256 i = 0; i < tokensLength; ++i) {

            uint256 token_elem_offset;
            uint256 token_elem_length;
            uint256 ii = (1 + i) * 32;

            assembly {
                token_elem_offset := mload(add(add(message, offset), ii))
                token_elem_length := mload(add(add(add(message, offset), 0x20), token_elem_offset))
            }

            IERC20[] memory tokensInner = new IERC20[](token_elem_length);

            for (uint256 k = 0; k < token_elem_length; ++k) {
                address _token;
                uint256 kk = k * 32;
                assembly {
                    _token := mload(
                        add(add(add(message, offset), token_elem_offset), add(0x40, kk))
                    )
                }
                tokensInner[k] = IERC20(_token);
            }

            tokens[i] = tokensInner;
        }
    }

    function _decodeCompleteWithdrawalsMsg_C(bytes memory message, uint256 offset)
        private
        pure
        returns (uint256[] memory middlewareTimesIndexes)
    {
        uint256 middlewareTimesIndexesLength;
        assembly {
            middlewareTimesIndexesLength := mload(add(message, offset))
        }
        middlewareTimesIndexes = new uint256[](middlewareTimesIndexesLength);

        for (uint256 i = 0; i < middlewareTimesIndexesLength; ++i) {
            uint256 elem;
            assembly {
                elem := mload(add(add(message, offset), mul(add(1, i), 0x20)))
            }
            middlewareTimesIndexes[i] = elem;
        }
    }

    function _decodeCompleteWithdrawalsMsg_D(bytes memory message, uint256 offset)
        private
        pure
        returns (bool[] memory receiveAsTokens)
    {
        uint256 receiveAsTokensLength;
        assembly {
            receiveAsTokensLength := mload(add(message, offset))
        }
        receiveAsTokens = new bool[](receiveAsTokensLength);

        for (uint256 i = 0; i < receiveAsTokensLength; ++i) {
            bool elem;
            assembly {
                elem := mload(add(add(message, offset), mul(add(1, i), 0x20)))
            }
            receiveAsTokens[i] = elem;
        }
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