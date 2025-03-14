//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IDelegationManagerTypes} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer-contracts/interfaces/ISignatureUtilsMixin.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {IERC20} from "@openzeppelin-v4-contracts/token/ERC20/IERC20.sol";
import {ISenderHooks} from "../interfaces/ISenderHooks.sol";
import {IRestakingConnector} from "../interfaces/IRestakingConnector.sol";


library EigenlayerMsgEncoders {

    /**
     * @dev Encodes a depositIntoStrategy() message for Eigenlayer's StrategyManager.sol contract
     * @param strategy Eigenlayer strategy to deposit into
     * @param token token associated with strategy
     * @param amount deposit amount
    */
    function encodeDepositIntoStrategyMsg(
        address strategy,
        address token,
        uint256 amount
    ) public pure returns (bytes memory) {
        return abi.encodeCall(
            // cast sig "depositIntoStrategy(address,address,uint256)" == 0xe7a050aa
            IStrategyManager.depositIntoStrategy,
            (
                IStrategy(strategy),
                IERC20(token),
                amount
            )
        );
    }

    /// @dev Encodes a queueWithdrawals() message for Eigenlayer's DelegationManager.sol contract
    /// @param queuedWithdrawalParams withdrawal parameters for queueWithdrawals() function call
    function encodeQueueWithdrawalsMsg(
        IDelegationManagerTypes.QueuedWithdrawalParams[] memory queuedWithdrawalParams
    ) public pure returns (bytes memory) {
        return abi.encodeCall(
            // cast sig "queueWithdrawals((address[],uint256[],address)[])"
            IDelegationManager.queueWithdrawals,
            (queuedWithdrawalParams)
        );
    }

    /**
     * @dev Encodes params for a completeWithdrawal() call to Eigenlayer's DelegationManager.sol
     * @param withdrawal withdrawal parameters for completeWithdrawals() function call
     * @param tokensToWithdraw tokens to withdraw.
     * @param receiveAsTokens determines whether to redeposit into Eigenlayer, or withdraw as tokens
     */
    function encodeCompleteWithdrawalMsg(
        IDelegationManagerTypes.Withdrawal memory withdrawal,
        IERC20[] memory tokensToWithdraw,
        bool receiveAsTokens
    ) public pure returns (bytes memory) {

        // Function Signature:
        //     completeQueuedWithdrawal(
        //         IDelegationManagerTypes.Withdrawal withdrawal,
        //         IERC20[] tokensToWithdraw,
        //         bool receiveAsTokens
        //     )
        // Where:
        //     struct Withdrawal {
        //         address staker;
        //         address delegatedTo;
        //         address withdrawer;
        //         uint256 nonce;
        //         uint32 startBlock;
        //         IStrategy[] strategies;
        //         uint256[] scaledShares;
        //     }

        return abi.encodeCall(
            // cast sig "completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],bool)" == 0xe4cc3f90
            IDelegationManager.completeQueuedWithdrawal,
            (
                withdrawal,
                tokensToWithdraw,
                receiveAsTokens
            )
        );
    }

    /// Array-ified version of completeWithdrawal
    function encodeCompleteWithdrawalsMsg(
        IDelegationManagerTypes.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        bool[] calldata receiveAsTokens
    ) public pure returns (bytes memory) {

        // Function Signature:
        //     completeQueuedWithdrawals(
        //         Withdrawal[] withdrawals,
        //         IERC20[][] tokens,
        //         bool[] receiveAsTokens
        //     )
        // Where:
        //     struct Withdrawal {
        //         address staker;
        //         address delegatedTo;
        //         address withdrawer;
        //         uint256 nonce;
        //         uint32 startBlock;
        //         IStrategy[] strategies;
        //         uint256[] shares;
        //     }

        return abi.encodeCall(
            // cast sig "completeQueuedWithdrawals((address,address,address,uint256,uint32,address[],uint256[])[],address[][],uint256[],bool[])" == 0x33404396
            IDelegationManager.completeQueuedWithdrawals,
            (
                withdrawals,
                tokens,
                receiveAsTokens
            )
        );
    }

    /**
     * @dev Encodes params for a delegateTo() call to Eigenlayer's DelegationManager.sol
     * @param operator entity to delegate to
     * @param approverSignatureAndExpiry operator approver's signature to delegate to them
     * @param approverSalt salt to ensure message signature is unique
     */
    function encodeDelegateTo(
        address operator,
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) public pure returns (bytes memory) {

        // Function Signature:
        //     delegateTo(
        //         address operator,
        //         SignatureWithExpiry memory approverSignatureAndExpiry,
        //         bytes32 approverSalt
        //     )
        // Where:
        //     struct SignatureWithExpiry {
        //         bytes signature;
        //         uint256 expiry;
        //     }

        return abi.encodeCall(
            // cast sig "delegateTo(address,(bytes,uint256),bytes32)" == 0xeea9064b
            IDelegationManager.delegateTo,
            (
                operator,
                approverSignatureAndExpiry,
                approverSalt
            )
        );
    }

    /// @dev Encodes params for a undelegate() call to Eigenlayer's DelegationManager.sol
    /// @param staker to undelegate (in this case EigenAgent). Msg.sender must be EigenAgent, Operator, or delegation approver
    function encodeUndelegateMsg(address staker) public pure returns (bytes memory) {
        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "undelegate(address)" == 0xda8be864
            IDelegationManager.undelegate.selector,
            staker
        );
        return message_bytes;
    }

    /// @dev Encodes params to mint an EigenAgent from the AgentFactory.sol contract. Can be called by anyone.
    /// @param recipient address to mint an EigenAgent to.
    function encodeMintEigenAgentMsg(address recipient) public pure returns (bytes memory) {
        // Note: use encodeWithSelector here as function selector differs from payload
        return abi.encodeWithSelector(
            // cast sig "mintEigenAgent(bytes)" == 0xcc15a557
            IRestakingConnector.mintEigenAgent.selector,
            recipient
        );
    }

    /*
     *
     *         L2 Withdrawal Transfers
     *
     *
    */

    /**
     * @dev encodes a message containing the AgentOwner when sending message from L1 to L2
     */
    function encodeTransferToAgentOwnerMsg(address agentOwner) public pure returns (bytes memory) {
        // Note: use encodeWithSelector here as function selector differs from payload
        return abi.encodeWithSelector(
            // cast sig "handleTransferToAgentOwner(bytes)" == 0xd8a85b48
            ISenderHooks.handleTransferToAgentOwner.selector,
            agentOwner
        );
    }

    /*
     *
     *         Rewards Claims
     *
     *
    */

    /**
     * @notice Claim rewards against a given root (read from _distributionRoots[claim.rootIndex]).
     * Earnings are cumulative so earners don't have to claim against all distribution roots they have earnings for,
     * they can simply claim against the latest root and the contract will calculate the difference between
     * their cumulativeEarnings and cumulativeClaimed. This difference is then transferred to recipient address.
     * @param claim The RewardsMerkleClaim to be processed.
     * Contains the root index, earner, token leaves, and required proofs
     * @param recipient The address recipient that receives the ERC20 rewards
     * @dev only callable by the valid claimer, that is
     * if claimerFor[claim.earner] is address(0) then only the earner can claim, otherwise only
     * claimerFor[claim.earner] can claim the rewards.
     */
    function encodeProcessClaimMsg(
        IRewardsCoordinator.RewardsMerkleClaim memory claim,
        address recipient
    ) public pure returns (bytes memory) {

        // struct RewardsMerkleClaim {
        //     uint32 rootIndex;
        //     uint32 earnerIndex;
        //     bytes earnerTreeProof;
        //     EarnerTreeMerkleLeaf earnerLeaf;
        //     uint32[] tokenIndices;
        //     bytes[] tokenTreeProofs;
        //     TokenTreeMerkleLeaf[] tokenLeaves;
        // }
        // struct EarnerTreeMerkleLeaf {
        //     address earner;
        //     bytes32 earnerTokenRoot;
        // }
        // struct TokenTreeMerkleLeaf {
        //     IERC20 token;
        //     uint256 cumulativeEarnings;
        // }

        return abi.encodeCall(
            // cast sig "processClaim((uint32,uint32,bytes,(address,bytes32),uint32[],bytes[],(address,uint256)[]), address)" == 0x3ccc861d
            IRewardsCoordinator.processClaim,
            (
                claim,
                recipient
            )
        );
    }

}
