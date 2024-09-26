//SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "@eigenlayer-contracts/interfaces/ISignatureUtils.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
        return abi.encodeWithSelector(
            // cast sig "depositIntoStrategy(address,address,uint256)" == 0xe7a050aa
            IStrategyManager.depositIntoStrategy.selector,
            strategy,
            token,
            amount
        );
    }

    /// @dev Encodes a queueWithdrawals() message for Eigenlayer's DelegationManager.sol contract
    /// @param queuedWithdrawalParams withdrawal parameters for queueWithdrawals() function call
    function encodeQueueWithdrawalsMsg(
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams
    ) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            // cast sig "queueWithdrawals((address[],uint256[],address)[])"
            IDelegationManager.queueWithdrawals.selector,
            queuedWithdrawalParams
        );
    }

    /**
     * @dev Encodes params for a completeWithdrawal() call to Eigenlayer's DelegationManager.sol
     * @param withdrawal withdrawal parameters for completeWithdrawals() function call
     * @param tokensToWithdraw tokens to withdraw.
     * @param middlewareTimesIndex used for slashing. Not used yet.
     * @param receiveAsTokens determines whether to redeposit into Eigenlayer, or withdraw as tokens
     */
    function encodeCompleteWithdrawalMsg(
        IDelegationManager.Withdrawal memory withdrawal,
        IERC20[] memory tokensToWithdraw,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    ) public pure returns (bytes memory) {

        // Function Signature:
        //     completeQueuedWithdrawal(
        //         IDelegationManager.Withdrawal withdrawal,
        //         IERC20[] tokensToWithdraw,
        //         uint256 middlewareTimesIndex,
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
        //         uint256[] shares;
        //     }

        return abi.encodeWithSelector(
            // cast sig "completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],uint256,bool)" == 0x60d7faed
            IDelegationManager.completeQueuedWithdrawal.selector,
            withdrawal,
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );
    }

    /// Array-ified version of completeWithdralw
    function encodeCompleteWithdrawalsMsg(
        IDelegationManager.Withdrawal[] calldata withdrawals,
        IERC20[][] calldata tokens,
        uint256[] calldata middlewareTimesIndexes,
        bool[] calldata receiveAsTokens
    ) public pure returns (bytes memory) {

        // Function Signature:
        //     completeQueuedWithdrawals(
        //         Withdrawal[] withdrawals,
        //         IERC20[][] tokens,
        //         uint256[] middlewareTimesIndexes,
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

        return abi.encodeWithSelector(
            // cast sig "completeQueuedWithdrawals((address,address,address,uint256,uint32,address[],uint256[])[],address[][],uint256[],bool[])" == 0x33404396
            IDelegationManager.completeQueuedWithdrawals.selector,
            withdrawals,
            tokens,
            middlewareTimesIndexes,
            receiveAsTokens
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
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
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

        return abi.encodeWithSelector(
            // cast sig "delegateTo(address,(bytes,uint256),bytes32)" == 0xeea9064b
            IDelegationManager.delegateTo.selector,
            operator,
            approverSignatureAndExpiry,
            approverSalt
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
     * @dev withdrawalTransferRoot commits to a Eigenlayer withdrawalRoot, amount and agentOwner
     * on L2 when first sending a completeWithdrawal() message so that when the withdrawan
     * funds return from L2 later, the bridge can lookup the user to transfer funds to.
     * @param withdrawalRoot is calculate by Eigenlayer during queueWithdrawals, needed to completeWithdrawal
     * @param agentOwner is the owner of the EigenAgent who deposits and withdraws from Eigenlayer
     */
    function calculateWithdrawalTransferRoot(
        bytes32 withdrawalRoot,
        address agentOwner // signer
    ) public pure returns (bytes32) {
        // encode signer into withdrawalTransferRoot
        return keccak256(abi.encode(withdrawalRoot, agentOwner));
    }

    /**
     * @dev Returns the same rewardsRoot calculated in in RestakingConnector during processClaims on L1
     * @param claim is the RewardsMerkleClaim struct used to processClaim in Eigenlayer.
     */
    function calculateRewardsRoot(IRewardsCoordinator.RewardsMerkleClaim memory claim)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(claim));
    }

    /**
     * @dev Returns the same rewardsTransferRoot calculated in RestakingConnector.
     * @param rewardsRoot keccak256(abi.encode(claim.rootIndex, claim.earnerIndex))
     * @param agentOwner owner of the EigenAgent executing completeWithdrawals
     */
    function calculateRewardsTransferRoot(
        bytes32 rewardsRoot,
        address agentOwner
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(rewardsRoot, agentOwner));
    }

    /**
     * @dev encodes a message containing the transferRoot when sending message from L1 to L2
     * @param transferRoot is a hash of:
     * (1) for withdrawal transfers: withdrawalRoot, amount, and agentOwner.
     * (2) for rewards transfers: rewardsRoot, rewardAmount, rewardToken, agentOwner.
     */
    function encodeTransferToAgentOwnerMsg(
        bytes32 transferRoot
    ) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            // cast sig "handleTransferToAgentOwner(bytes)" == 0xd8a85b48
            ISenderHooks.handleTransferToAgentOwner.selector,
            transferRoot
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

        return abi.encodeWithSelector(
            // cast sig "processClaim((uint32,uint32,bytes,(address,bytes32),uint32[],bytes[],(address,uint256)[]), address)" == 0x3ccc861d
            IRewardsCoordinator.processClaim.selector,
            claim,
            recipient
        );
    }

}