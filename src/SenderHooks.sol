// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {ISenderHooks} from "./interfaces/ISenderHooks.sol";
import {EigenlayerMsgDecoders, TransferToAgentOwnerMsg} from "./utils/EigenlayerMsgDecoders.sol";
import {FunctionSelectorDecoder} from "./utils/FunctionSelectorDecoder.sol";
import {Adminable} from "./utils/Adminable.sol";


/// @title Sender Hooks: processes SenderCCIP messages and stores state
contract SenderHooks is Initializable, Adminable, EigenlayerMsgDecoders {

    /// @notice links transferRoot to amounts[], tokensL2[], agentOwners for withdrawals and rewards
    mapping(bytes32 transferRoot => uint256[] amount) public transferCommitmentsAmount;
    mapping(bytes32 transferRoot => address[] tokenL2) public transferCommitmentsTokenL2;
    mapping(bytes32 transferRoot => address agentOwner) public transferCommitmentsAgentOwner;

    /// @notice tracks whether transferRoots have been used, marking a transfer complete.
    mapping(bytes32 => bool) public transferRootsSpent;

    mapping(bytes4 => uint256) internal _gasLimitsForFunctionSelectors;

    address internal _senderCCIP;

    /// @notice lookup L2 token addresses of bridgeable tokens
    mapping(address bridgeTokenL1 => address bridgeTokenL2) public bridgeTokensL1toL2;

    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);

    event WithdrawalTransferRootCommitted(
        bytes32 indexed withdrawalTransferRoot,
        address signer
    );

    event RewardsTransferRootCommitted(
        bytes32 indexed rewardsTransferRoot,
        address signer
    );

    error AddressZero(string msg);
    error OnlySendFundsForDeposits(string msg);

    constructor() {
        _disableInitializers();
    }

    /// @param _bridgeTokenL1 address of the bridging token's L1 contract.
    /// @param _bridgeTokenL2 address of the bridging token's L2 contract.
    function initialize(address _bridgeTokenL1, address _bridgeTokenL2) external initializer {

        if (_bridgeTokenL1 == address(0))
            revert AddressZero("_bridgeTokenL1 cannot be address(0)");

        if (_bridgeTokenL2 == address(0))
            revert AddressZero("_bridgeTokenL2 cannot be address(0)");

        bridgeTokensL1toL2[_bridgeTokenL1] = _bridgeTokenL2;

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

    /**
     * @notice outlines which token pairs are bridgeable, and their L1 and L2 addresses
     * @param _bridgeTokenL1 bridging token's address on L1
     * @param _bridgeTokenL2 bridging token's address on L2
     */
    function setBridgeTokens(address _bridgeTokenL1, address _bridgeTokenL2) external onlyOwner {

        if (_bridgeTokenL1 == address(0))
            revert AddressZero("_bridgeTokenL1 cannot be address(0)");

        if (_bridgeTokenL2 == address(0))
            revert AddressZero("_bridgeTokenL2 cannot be address(0)");

        bridgeTokensL1toL2[_bridgeTokenL1] = _bridgeTokenL2;
    }

    /**
     * @notice clears a token pair
     * @param _bridgeTokenL1 bridging token's address on L1
     */
    function clearBridgeTokens(address _bridgeTokenL1) external onlyOwner {
        delete bridgeTokensL1toL2[_bridgeTokenL1];
    }

    /*
     *
     *                L2 Withdrawal Transfers / Rewards Transfers
     *
     *
    */

    /**
     * @param transferRoot is calculated when dispatching a completeWithdrawal message.
     * A transferRoot may be either a rewardsTransferRoot or withdrawalsTransferRoot depending on
     * whether we are sending a completeWithdrawal message, or a rewards claimProcess message.
     */
    function isTransferRootSpent(bytes32 transferRoot) external view returns (bool) {
        return transferRootsSpent[transferRoot];
    }

    /**
     * @dev This function handles inbound L1 -> L2 completeWithdrawal messages after Eigenlayer has
     * withdrawn funds, and the L1 bridge has bridged them back to L2.
     * It receives a transferRoot and matches it with the committed transferRoot
     * to verify which user to transfer the withdrawn funds (or rewards claims) to.
     */
    function handleTransferToAgentOwner(bytes memory message)
        external
        returns (ISenderHooks.FundsTransfer[] memory)
    {

        TransferToAgentOwnerMsg memory transferToAgentOwnerMsg = decodeTransferToAgentOwnerMsg(message);
        bytes32 transferRoot = transferToAgentOwnerMsg.transferRoot;

        require(
            transferRootsSpent[transferRoot] == false,
            "SenderHooks.handleTransferToAgentOwner: TransferRoot already used"
        );

        // Read the withdrawalTransferRoot (or rewardsTransferRoot) that signer previously committed to.
        ISenderHooks.FundsTransfer[] memory fundsTransfers = getFundsTransferCommitment(transferRoot);

        // Mark withdrawalTransferRoot (or rewardsTransferRoot) as spent to prevent double withdrawals/claims
        transferRootsSpent[transferRoot] = true;
        delete transferCommitmentsAmount[transferRoot];
        delete transferCommitmentsTokenL2[transferRoot];
        delete transferCommitmentsAgentOwner[transferRoot];

        return fundsTransfers;
    }

    /**
     * @dev Hook that executes in outbound sendMessagePayNative calls.
     * if the outbound message is completeQueueWithdrawal, it will calculate a transferRoot
     * and store information about the amount and owner of the EigenAgent doing the withdrawal to
     * transfer withdrawals to later (or rewards claims).
     * @param message is the outbound message passed to CCIP's _buildCCIPMessage function
     * @param amount is the amount of token being sent
     */
    function beforeSendCCIPMessage(
        bytes memory message,
        uint256 amount
    ) external onlySenderCCIP returns (uint256 gasLimit) {

        bytes4 functionSelector = FunctionSelectorDecoder.decodeFunctionSelector(message);

        if (functionSelector != IStrategyManager.depositIntoStrategy.selector) {
            // check tokens are only bridged for deposit calls
            if (amount > 0) revert OnlySendFundsForDeposits("Only send funds for deposit messages");
        }

        if (functionSelector == IDelegationManager.completeQueuedWithdrawal.selector) {
            // 0x60d7faed
            _commitWithdrawalTransferRootInfo(message);
        } else if (functionSelector == IRewardsCoordinator.processClaim.selector) {
            // 0x3ccc861d
            _commitRewardsTransferRootInfo(message);
        }

        return getGasLimitForFunctionSelector(functionSelector);
    }

    /**
     * @dev Gets FundsTransfer structs (amount, tokenl2, agentOwner) associated with a transferRoot
     * @param transferRoot is calculated when dispatching a completeWithdrawal message.
     * A transferRoot may be either a rewardsTransferRoot or withdrawalsTransferRoot depending on
     * whether we are sending a completeWithdrawal message, or a rewards claimProcess message.
     * @return transferTokensArray is an array of FundsTransfer(amount, tokenL2, agentOwner) structs
     */
    function getFundsTransferCommitment(bytes32 transferRoot)
        public
        view
        returns (ISenderHooks.FundsTransfer[] memory transferTokensArray)
    {
        uint256[] memory amounts = transferCommitmentsAmount[transferRoot];
        address[] memory tokensL2 = transferCommitmentsTokenL2[transferRoot];
        address agentOwner = transferCommitmentsAgentOwner[transferRoot];

        // instantiate array size. amounts.length == tokensL2.length by construction
        transferTokensArray = new ISenderHooks.FundsTransfer[](amounts.length);

        for (uint256 i = 0; i < amounts.length; ++i) {
            transferTokensArray[i] = ISenderHooks.FundsTransfer({
                amount: amounts[i],
                tokenL2: tokensL2[i],
                agentOwner: agentOwner
            });
        }
    }

    /**
     * @dev Returns the same withdrawalTransferRoot calculated in RestakingConnector.
     * @param withdrawalRoot withdrawalRoot calculated by Eigenlayer to verify withdrawals.
     * @param agentOwner owner of the EigenAgent executing completeWithdrawals
     */
    function calculateWithdrawalTransferRoot(
        bytes32 withdrawalRoot,
        address agentOwner
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(withdrawalRoot, agentOwner));
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
     *
     *
     *                 Private Functions
     *
     *
     */

    function _commitWithdrawalTransferRootInfo(bytes memory message) private {

        (
            IDelegationManager.Withdrawal memory withdrawal,
            IERC20[] memory tokensToWithdraw,
            , // middlewareTimesIndex
            bool receiveAsTokens, // receiveAsTokens
            address signer, // signer
            , // expiry
            // signature
        ) = decodeCompleteWithdrawalMsg(message);

        // @param receiveAsTokens is an Eigenlayer parameter that determines whether a user is withdraws
        // tokens (receiveAsTokens = true), or re-deposits tokens as part of redelegating to an Operator.
        // If receveAsTokens = false, we don't need to do anything.
        if (receiveAsTokens) {

            uint256 n; // track bridgeable tokens index

            ISenderHooks.FundsTransfer[] memory fundsTransfersArray =
                new ISenderHooks.FundsTransfer[](_numBridgeableTokens(tokensToWithdraw));

            for (uint256 i = 0; i < tokensToWithdraw.length; ++i) {

                uint256 amount = withdrawal.shares[i];
                address tokenL2 = bridgeTokensL1toL2[address(tokensToWithdraw[i])];
                // Check whether tokenToWithdraw is bridgeable:
                if (tokenL2 != address(0)) {

                    fundsTransfersArray[n] = ISenderHooks.FundsTransfer({
                        amount: amount,
                        tokenL2: tokenL2,
                        agentOwner: signer
                    });

                    ++n;
                }
            }

            // Calculate withdrawalTransferRoot: hash(withdrawalRoot, amount, tokenL2, signer)
            // and commit to it on L2, so that when the withdrawalTransferRoot message is
            // returned from L1 we can lookup and verify which AgentOwner to transfer funds to.
            bytes32 withdrawalTransferRoot = calculateWithdrawalTransferRoot(
                _calculateWithdrawalRoot(withdrawal),
                signer // agentOwner
            );
            // This prevents griefing attacks where other users put in withdrawalRoot entries
            // with the wrong agentOwner details, preventing completeWithdrawals

            require(
                transferRootsSpent[withdrawalTransferRoot] == false,
                "SenderHooks._commitWithdrawalTransferRootInfo: TransferRoot already used"
            );

            // Commit to (amount, tokenL2, agentOwner) before sending completeWithdrawal message,
            _setFundsTransferCommitment(withdrawalTransferRoot, fundsTransfersArray);

            emit WithdrawalTransferRootCommitted(withdrawalTransferRoot, signer);
        }
    }

    function _commitRewardsTransferRootInfo(bytes memory message) private {

        (
            IRewardsCoordinator.RewardsMerkleClaim memory claim,
            , // address recipient (EigenAgent)
            address signer, // signer
            , // expiry
            // signature
        ) = decodeProcessClaimMsg(message);

        uint256 n = 0; // index to keep track of bridgeable tokens

        ISenderHooks.FundsTransfer[] memory fundsTransfersArray =
            new ISenderHooks.FundsTransfer[](_numBridgeableTokenLeaves(claim.tokenLeaves));

        for (uint32 j = 0; j < claim.tokenLeaves.length; ++j) {
            // Only bridgeable tokens will be bridged back to L2.
            // Other L1 tokens will be claimed and transferred to AgentOwner on L1
            // and do not need a TransferRoot commitment.
            uint256 rewardAmount = claim.tokenLeaves[j].cumulativeEarnings;
            address rewardToken = address(claim.tokenLeaves[j].token);
            address tokenL2 = bridgeTokensL1toL2[rewardToken];
            // Check whether tokenToWithdraw is bridgeable:
            if (tokenL2 != address(0)) {

                fundsTransfersArray[n] = ISenderHooks.FundsTransfer({
                    amount: rewardAmount,
                    tokenL2: tokenL2,
                    agentOwner: signer // signer is owner of recipient (EigenAgent)
                });

                ++n;
            }
        }

        // Calculate rewardsTransferRoot and commit to it on L2, so that when the
        // rewardsTransferRoot message is returned from L1 we can lookup and verify
        // which AgentOwner to transfer rewards to.
        bytes32 rewardsTransferRoot = calculateRewardsTransferRoot(
            _calculateRewardsRoot(claim),
            signer
        );
        // This prevents griefing attacks where other users input transferRoot entries
        // with the wrong agentOwner address after a withdrawal or processClaim has been sent.

        require(
            transferRootsSpent[rewardsTransferRoot] == false,
            "SenderHooks._commitRewardsTransferRootInfo: TransferRoot already used"
        );

        // Commit rewardsTransferRoot to fundsTransferArray before sending processClaim message,
        _setFundsTransferCommitment(rewardsTransferRoot, fundsTransfersArray);

        emit RewardsTransferRootCommitted(rewardsTransferRoot, signer);
    }

    /**
     * @dev Sets FundsTransfer structs (amount, tokenl2, agentOwner) associated with a transferRoot
     * only bridgeable tokens are saved. Non bridgeable tokens will not be stored.
     * @param transferRoot is calculated when dispatching a completeWithdrawal message.
     * A transferRoot may be either a rewardsTransferRoot or withdrawalsTransferRoot depending on
     * whether we are sending a completeWithdrawal message, or a rewards claimProcess message.
     * @param transferTokensArray is an array of FundsTransfer(amount, tokenL2, agentOwner) structs
     * Assumes all elements have non-zero fields for: amount, tokenl2, agentOwner
     */
    function _setFundsTransferCommitment(
        bytes32 transferRoot,
        ISenderHooks.FundsTransfer[] memory transferTokensArray
    ) private {

        if (transferTokensArray.length > 0) {

            uint256[] memory amounts = new uint256[](transferTokensArray.length);
            address[] memory tokensL2 = new address[](transferTokensArray.length);
            address agentOwner = transferTokensArray[0].agentOwner;

            for (uint32 i = 0; i < transferTokensArray.length; ++i) {
                amounts[i] = transferTokensArray[i].amount;
                tokensL2[i] = transferTokensArray[i].tokenL2;
            }

            transferCommitmentsAmount[transferRoot] = amounts;
            transferCommitmentsTokenL2[transferRoot] = tokensL2;
            transferCommitmentsAgentOwner[transferRoot] = agentOwner;
        }
    }

    /**
     * @dev gets number of bridgeable tokens from an array that contains both bridgeable
     * and non-bridgeable tokens for withdrawals
     */
    function _numBridgeableTokens(IERC20[] memory tokens) private view returns (uint256 num) {
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (bridgeTokensL1toL2[address(tokens[i])] != address(0)) {
                ++num;
            }
        }
    }

    /**
     * @dev gets number of bridgeable tokens from an array that contains both bridgeable
     * and non-bridgeable tokens for rewards claims
     */
    function _numBridgeableTokenLeaves(IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeafs)
        private
        view
        returns (uint256 num)
    {
        for (uint256 i = 0; i < tokenLeafs.length; ++i) {
            if (bridgeTokensL1toL2[address(tokenLeafs[i].token)] != address(0)) {
                ++num;
            }
        }
    }

    /**
     * @dev Returns the same withdrawalRoot calculated in Eigenlayer's DelegationManager during withdrawal
     * @param withdrawal is the Withdrawal struct used to completeWithdralwas in Eigenlayer.
     */
    function _calculateWithdrawalRoot(IDelegationManager.Withdrawal memory withdrawal)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(withdrawal));
    }

    /**
     * @dev Returns the same rewardsRoot calculated in in RestakingConnector during processClaims on L1
     * @param claim is the RewardsMerkleClaim struct used to processClaim in Eigenlayer.
     */
    function _calculateRewardsRoot(IRewardsCoordinator.RewardsMerkleClaim memory claim)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(claim));
    }
}

