// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {ISenderHooks} from "./interfaces/ISenderHooks.sol";
import {ISenderCCIP} from "./interfaces/ISenderCCIP.sol";
import {EigenlayerMsgDecoders, TransferToAgentOwnerMsg} from "./utils/EigenlayerMsgDecoders.sol";
import {FunctionSelectorDecoder} from "./utils/FunctionSelectorDecoder.sol";
import {Adminable} from "./utils/Adminable.sol";


/// @title Sender Hooks: processes SenderCCIP messages and stores state
contract SenderHooks is Initializable, Adminable, EigenlayerMsgDecoders {

    /// @notice stores information about agentOwner (withdrawals), or recipient (rewards)
    mapping(bytes32 => ISenderHooks.FundsTransfer) public transferCommitments;

    /// @notice tracks whether transferRoots have been used, marking a transfer complete.
    mapping(bytes32 => bool) public transferRootsSpent;

    mapping(bytes4 => uint256) internal _gasLimitsForFunctionSelectors;

    address internal _senderCCIP;

    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);
    event SendingFundsToAgentOwner(address indexed, uint256 indexed);
    event WithdrawalTransferRootCommitted(
        bytes32 indexed withdrawalTransferRoot,
        address indexed withdrawer,
        uint256 amount,
        address signer
    );
    event RewardsTransferRootCommitted(
        bytes32 indexed rewardsTransferRoot,
        address indexed recipient,
        uint256 amount,
        address signer
    );

    error AddressZero(string msg);
    error OnlySendFundsForDeposits(string msg);

    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Adminable_init();
    }

    modifier onlySenderCCIP() {
        require(msg.sender == _senderCCIP, "not called by SenderCCIP");
        _;
    }

    function getSenderCCIP() external view returns (address) {
        return _senderCCIP;
    }

    /// @param newSenderCCIP address of the SenderCCIP contract.
    function setSenderCCIP(address newSenderCCIP) external onlyOwner {
        if (newSenderCCIP == address(0))
            revert AddressZero("SenderCCIP cannot be address(0)");

        _senderCCIP = newSenderCCIP;
    }

    /**
     * @dev Retrieves estimated gasLimits for different L2 restaking functions, e.g:
     * - depositIntoStrategy(address,address,uint256) == 0xe7a050aa
     * - mintEigenAgent(bytes) == 0xcc15a557
     * - queueWithdrawals((address[],uint256[],address)[]) == 0x0dd8dd02
     * - completeQueuedWithdrawal(withdrawal,address[],uint256,bool) == 0x60d7faed
     * - delegateTo(address,(bytes,uint256),bytes32) == 0xeea9064b
     * - undelegate(address) == 0xda8be864
     * @param functionSelector bytes4 functionSelector to get estimated gasLimits for.
     * @return gasLimit a default gasLimit of 200_000 functionSelector parameter finds no matches.
     */
    function getGasLimitForFunctionSelector(bytes4 functionSelector)
        public
        view
        returns (uint256)
    {
        uint256 gasLimit = _gasLimitsForFunctionSelectors[functionSelector];
        return (gasLimit > 0) ? gasLimit : 200_000;
    }

    /**
     * @dev Sets gas limits for various functions. Requires an array of bytes4 function selectors and
     * a corresponding array of gas limits.
     * @param functionSelectors list of bytes4 function selectors
     * @param gasLimits list of gasLimits to set the gasLimits for functions to call
     */
    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) external onlyOwner {
        require(functionSelectors.length == gasLimits.length, "input arrays must have the same length");
        for (uint256 i = 0; i < gasLimits.length; ++i) {
            _gasLimitsForFunctionSelectors[functionSelectors[i]] = gasLimits[i];
            emit SetGasLimitForFunctionSelector(functionSelectors[i], gasLimits[i]);
        }
    }

    /*
     *
     *                L2 Withdrawal Transfers / Rewards Transfers
     *
     *
    */

    /**
     * @dev Returns funds transfer fields (amount, recipient) associated with
     * the transferRoot that was committed.
     * @param transferRoot is calculated when dispatching a completeWithdrawal message.
     * A transferRoot may be either a rewardsTransferRoot or withdrawalsTransferRoot depending on
     * whether we are sending a completeWithdrawal message, or a rewards claimProcess message.
     */
    function getFundsTransferCommitment(bytes32 transferRoot) external view returns (
        ISenderHooks.FundsTransfer memory
    ) {
        return transferCommitments[transferRoot];
    }

    /**
     * @param transferRoot is calculated when dispatching a completeWithdrawal message.
     * A transferRoot may be either a rewardsTransferRoot or withdrawalsTransferRoot depending on
     * whether we are sending a completeWithdrawal message, or a rewards claimProcess message.
     */
    function isTransferRootSpent(bytes32 transferRoot) external view returns (bool) {
        return transferRootsSpent[transferRoot];
    }

    /**
     * @dev Returns the same withdrawalTransferRoot calculated in RestakingConnector.
     * @param withdrawalRoot withdrawalRoot calculated by Eigenlayer to verify withdrawals.
     * @param amount amount in the withdrawal
     * @param agentOwner owner of the EigenAgent executing completeWithdrawals
     */
    function calculateWithdrawalTransferRoot(
        bytes32 withdrawalRoot,
        uint256 amount,
        address agentOwner
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(withdrawalRoot, amount, agentOwner));
    }

    /**
     * @dev Returns the same rewardsTransferRoot calculated in RestakingConnector.
     * @param rewardsRoot keccak256(abi.encode(claim.rootIndex, claim.earnerIndex))
     * @param rewardAmount amount of rewards
     * @param rewardToken token address of reward token
     * @param agentOwner owner of the EigenAgent executing completeWithdrawals
     */
    function calculateRewardsTransferRoot(
        bytes32 rewardsRoot,
        uint256 rewardAmount,
        address rewardToken,
        address agentOwner
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(rewardsRoot, rewardAmount, rewardToken, agentOwner));
    }

    /**
     * @dev This function handles inbound L1 -> L2 completeWithdrawal messages after Eigenlayer has
     * withdrawn funds, and the L1 bridge has bridged them back to L2.
     * It receives a transferRoot and matches it with the committed transferRoot
     * to verify which user to transfer the withdrawn funds (or rewards claims) to.
     */
    function handleTransferToAgentOwner(bytes memory message) external returns (address, uint256) {

        TransferToAgentOwnerMsg memory transferToAgentOwnerMsg = decodeTransferToAgentOwnerMsg(message);

        bytes32 transferRoot = transferToAgentOwnerMsg.transferRoot;

        require(
            transferRootsSpent[transferRoot] == false,
            "SenderHooks.handleTransferToAgentOwner: TransferRoot already used"
        );

        // Read the withdrawalTransferRoot (or rewardsTransferRoot) that signer previously committed to.
        ISenderHooks.FundsTransfer memory fundsTransfer = transferCommitments[transferRoot];

        // Mark withdrawalTransferRoot (or rewardsTransferRoot) as spent to prevent double withdrawals/claims
        transferRootsSpent[transferRoot] = true;
        delete transferCommitments[transferRoot];

        emit SendingFundsToAgentOwner(fundsTransfer.agentOwner, fundsTransfer.amount);

        return (fundsTransfer.agentOwner, fundsTransfer.amount);
    }

    /**
     * @dev Hook that executes in outbound sendMessagePayNative calls.
     * if the outbound message is completeQueueWithdrawal, it will calculate a transferRoot
     * and store information about the amount and owner of the EigenAgent doing the withdrawal to
     * transfer withdrawals to later (or rewards claims).
     * @param message is the outbound message passed to CCIP's _buildCCIPMessage function
     * @param tokenL2 token on L2 for TransferToAgentOwner callback
     */
    function beforeSendCCIPMessage(
        bytes memory message,
        address tokenL2,
        uint256 amount
    ) external onlySenderCCIP returns (uint256 gasLimit) {

        bytes4 functionSelector = FunctionSelectorDecoder.decodeFunctionSelector(message);

        if (functionSelector != IStrategyManager.depositIntoStrategy.selector) {
            // check tokens are only bridged for deposit calls
            if (amount > 0) revert OnlySendFundsForDeposits("Only send funds for deposit messages");
        }

        if (functionSelector == IDelegationManager.completeQueuedWithdrawal.selector) {
            // 0x60d7faed
            _commitWithdrawalTransferRootInfo(message, tokenL2);
        } else if (functionSelector == IRewardsCoordinator.processClaim.selector) {
            // 0x3ccc861d
            _commitRewardsTransferRootInfo(message, tokenL2);
        }

        return getGasLimitForFunctionSelector(functionSelector);
    }

    function _commitWithdrawalTransferRootInfo(bytes memory message, address tokenL2) private {

        require(
            tokenL2 != address(0),
            "SenderHooks._commitWithdrawalTransferRootInfo: cannot commit tokenL2 as address(0)"
        );

        (
            IDelegationManager.Withdrawal memory withdrawal,
            IERC20[] memory tokensToWithdraw,
            , // middlewareTimesIndex
            bool receiveAsTokens, // receiveAsTokens
            address signer, // signer
            , // expiry
            // signature
        ) = decodeCompleteWithdrawalMsg(message);

        address bridgeTokenL1 = ISenderCCIP(_senderCCIP).bridgeTokenL1();

        for (uint256 i = 0; i < tokensToWithdraw.length; ++i) {
            // Assume only one token (BridgeToken) is bridgeable:
            // Otherwise we need to track L1 and L2 addresses of all bridgeable tokens
            if (receiveAsTokens && address(tokensToWithdraw[i]) == bridgeTokenL1) {

                // @param receiveAsTokens is an Eigenlayer parameter that determines whether a user is withdraws
                // tokens (receiveAsTokens = true), or re-deposits tokens as part of redelegating to an Operator.
                // This state is only reached when withdrawing BridgeTokens back to L2, not for re-deposits.

                // Calculate withdrawalTransferRoot: hash(withdrawalRoot, amount, signer)
                // and commit to it on L2, so that when the withdrawalTransferRoot message is
                // returned from L1 we can lookup and verify which AgentOwner to transfer funds to.
                bytes32 withdrawalTransferRoot = calculateWithdrawalTransferRoot(
                    _calculateWithdrawalRoot(withdrawal),
                    withdrawal.shares[i], // amount
                    signer // agentOwner
                );
                // This prevents griefing attacks where other users put in withdrawalRoot entries
                // with the wrong agentOwner address, preventing completeWithdrawals

                require(
                    transferRootsSpent[withdrawalTransferRoot] == false,
                    "SenderHooks._commitWithdrawalTransferRootInfo: TransferRoot already used"
                );

                // Commit to WithdrawalTransfer(withdrawer, amount, token, owner) before sending completeWithdrawal message,
                transferCommitments[withdrawalTransferRoot] = ISenderHooks.FundsTransfer({
                    amount: withdrawal.shares[i],
                    agentOwner: signer // signer is owner of EigenAgent, used in handleTransferToAgentOwner
                });

                emit WithdrawalTransferRootCommitted(
                    withdrawalTransferRoot,
                    withdrawal.withdrawer, // eigenAgent
                    withdrawal.shares[i], // amount
                    signer // agentOwner
                );
            }
        }
    }


    function _commitRewardsTransferRootInfo(bytes memory message, address tokenL2) private {

        require(
            tokenL2 != address(0),
            "SenderHooks._commitRewardsTransferRootInfo: cannot commit tokenL2 as address(0)"
        );

        (
            IRewardsCoordinator.RewardsMerkleClaim memory claim,
            address recipient, // EigenAgent
            address signer, // signer
            , // expiry
            // signature
        ) = decodeProcessClaimMsg(message);

        address bridgeTokenL1 = ISenderCCIP(_senderCCIP).bridgeTokenL1();

        for (uint32 i = 0; i < claim.tokenLeaves.length; ++i) {

            uint256 rewardAmount = claim.tokenLeaves[i].cumulativeEarnings;
            address rewardToken = address(claim.tokenLeaves[i].token);

            // Assume only one reward token is bridgeable (BridgeToken)
            // Otherwise we need to track L1 and L2 addresses of all bridgeable tokens
            if (rewardToken == bridgeTokenL1) {
                // Calculate rewardsTransferRoot and commit to it on L2, so that when the
                // rewardsTransferRoot message is returned from L1 we can lookup and verify
                // which AgentOwner to transfer rewards to.
                bytes32 rewardsTransferRoot = calculateRewardsTransferRoot(
                    _calculateRewardsRoot(claim),
                    rewardAmount,
                    rewardToken,
                    signer
                );
                // This prevents griefing attacks where other users input transferRoot entries
                // with the wrong agentOwner address after a withdrawal or processClaim has been sent.

                require(
                    transferRootsSpent[rewardsTransferRoot] == false,
                    "SenderHooks._commitRewardsTransferRootInfo: TransferRoot already used"
                );

                // Commit to RewardsTransfer (amount, agentOwner) before sending processClaim message,
                transferCommitments[rewardsTransferRoot] = ISenderHooks.FundsTransfer({
                    amount: rewardAmount,
                    agentOwner: signer // signer is owner of recipient (EigenAgent)
                });

                emit RewardsTransferRootCommitted(
                    rewardsTransferRoot,
                    recipient, // recipient
                    rewardAmount, // amount
                    signer // signer
                );
            } else {
                // Only the BridgeToken will be bridged back to L2.
                // Other L1 tokens will be claimed and transferred to AgentOwner on L1
                // and do not need a TransferRoot commitment.
            }

        }
    }

    /**
     * @dev Returns the same withdrawalRoot calculated in Eigenlayer's DelegationManager during withdrawal
     * @param withdrawal is the Withdrawal struct used to completeWithdralwas in Eigenlayer.
     */
    function _calculateWithdrawalRoot(
        IDelegationManager.Withdrawal memory withdrawal
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(withdrawal));
    }

    /**
     * @dev Returns the same rewardsRoot calculated in in RestakingConnector during processClaims on L1
     * @param claim is the RewardsMerkleClaim struct used to processClaim in Eigenlayer.
     */
    function _calculateRewardsRoot(
        IRewardsCoordinator.RewardsMerkleClaim memory claim
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(claim));
    }
}

