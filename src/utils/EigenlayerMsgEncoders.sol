//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
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

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "depositIntoStrategy(address,address,uint256)" == 0xe7a050aa
            IStrategyManager.depositIntoStrategy.selector,
            strategy,
            token,
            amount
        );
        return message_bytes;
    }

    /// @dev Encodes a queueWithdrawals() message for Eigenlayer's DelegationManager.sol contract
    /// @param queuedWithdrawalParams withdrawal parameters for queueWithdrawals() function call
    function encodeQueueWithdrawalsMsg(
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams
    ) public pure returns (bytes memory) {

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "queueWithdrawals((address[],uint256[],address)[])"
            IDelegationManager.queueWithdrawals.selector,
            queuedWithdrawalParams
        );

        return message_bytes;
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

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],uint256,bool)" == 0x60d7faed
            IDelegationManager.completeQueuedWithdrawal.selector,
            withdrawal,
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );

        return message_bytes;
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

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "delegateTo(address,(bytes,uint256),bytes32)" == 0xeea9064b
            IDelegationManager.delegateTo.selector,
            operator,
            approverSignatureAndExpiry,
            approverSalt
        );
        return message_bytes;
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
    function encodeMintEigenAgent(address recipient) public pure returns (bytes memory) {

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "mintEigenAgent(bytes)" == 0xcc15a557
            IRestakingConnector.mintEigenAgent.selector,
            recipient
        );
        return message_bytes;
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
     * @param amount is the amount withdrawan
     * @param agentOwner is the owner of the EigenAgent who deposits and withdraws from Eigenlayer
     */
    function calculateWithdrawalTransferRoot(
        bytes32 withdrawalRoot,
        uint256 amount,
        address agentOwner // signer
    ) public pure returns (bytes32) {
        // encode signer into withdrawalTransferRoot
        return keccak256(abi.encode(withdrawalRoot, amount, agentOwner));
    }

    /// @dev encodes a message containing the withdrawalTransferRoot when sending message from L1 to L2
    /// @param withdrawalTransferRoot is a hash of withdrawalRoot, amount, and agentOwner.
    function encodeHandleTransferToAgentOwnerMsg(
        bytes32 withdrawalTransferRoot
    ) public pure returns (bytes memory) {

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "handleTransferToAgentOwner(bytes)" == 0xd8a85b48
            ISenderHooks.handleTransferToAgentOwner.selector,
            withdrawalTransferRoot
        );
        return message_bytes;
    }
}
