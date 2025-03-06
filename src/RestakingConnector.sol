// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin-v5-contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin-v47-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-v47-contracts/token/ERC20/utils/SafeERC20.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {ISignatureUtils} from "@eigenlayer-contracts/interfaces/ISignatureUtils.sol";

import {RestakingConnectorStorage} from "./RestakingConnectorStorage.sol";
import {FunctionSelectorDecoder} from "./utils/FunctionSelectorDecoder.sol";
import {EigenlayerMsgDecoders, DelegationDecoders} from "./utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "./utils/EigenlayerMsgEncoders.sol";

import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";



contract RestakingConnector is
    Initializable,
    EigenlayerMsgDecoders,
    RestakingConnectorStorage
{
    using SafeERC20 for IERC20;

    event SetQueueWithdrawalBlock(address indexed, uint256 indexed, uint256 indexed);
    event SetUndelegateBlock(address indexed, uint256 indexed, uint256 indexed);
    event SendingRewardsToAgentOwnerOnL1(address indexed, address indexed, uint256 indexed);
    event SendingWithdrawalToAgentOwnerOnL1(address indexed, address indexed, uint256 indexed);

    error UnsupportedFunctionCall(bytes4 functionSelector);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IAgentFactory _agentFactory,
        address _bridgeTokenL1,
        address _bridgeTokenL2
    ) external initializer {
        __RestakingConnectorStorage_init(_agentFactory, _bridgeTokenL1, _bridgeTokenL2);
    }

    /**
     * @dev Retrieves the block.number where queueWithdrawal occurred. Needed as the time when
     * queueWithdrawal message is dispatched differs from the time the message executes on L1.
     * @param staker is the EigenAgent staking into Eigenlayer
     * @param nonce is the withdrawal nonce Eigenlayer keeps track of in DelegationManager.sol
     */
    function getQueueWithdrawalBlock(address staker, uint256 nonce) external view returns (uint256) {
        return _withdrawalBlock[staker][nonce];
    }

    /**
     * @dev Checkpoint the actual block.number before queueWithdrawal happens
     * When dispatching a L2 -> L1 message to queueWithdrawal, the block.number varies depending
     * on how long it takes to bridge. We need the block.number to in the following step to
     * create the withdrawalRoot used to completeWithdrawal.
     * @param staker is the EigenAgent staking into Eigenlayer
     * @param nonce is the withdrawal nonce Eigenlayer keeps track of in DelegationManager.sol
     * accessible by calling cumulativeWithdrawalsQueued()
     * @param blockNumber is the block.number where withdrawal is queued. Needed to completeWithdrawal
     */
    function setQueueWithdrawalBlock(
        address staker,
        uint256 nonce,
        uint256 blockNumber
    ) external onlyAdminOrOwner {
        _withdrawalBlock[staker][nonce] = blockNumber;
        emit SetQueueWithdrawalBlock(staker, nonce, blockNumber);
    }

    /*
     *
     *                EigenAgent <> Eigenlayer Handlers
     *
     *
    */

   /**
     * @dev This function is only called by ReceiverCCIP.
     * @notice This function matches a function selector, then forwards CCIP Eigenlayer messages
     * to the RestakingConnector which deserializes the rest of the message and
     * forwards it to the user's EigenAgent for execution.
     * @param any2EvmMessage is the message the CCIP bridge receives and forwards to this function
     * @return transferTokensInfo contains info for the bridge contract
     * to bridge withdrawals or rewards back to L2, and transfer the funds to the AgentOwner on L2.
     */
    function dispatchMessageToEigenAgent(Client.Any2EVMMessage memory any2EvmMessage)
        external
        override
        onlyReceiverCCIP
        returns (IRestakingConnector.TransferTokensInfo memory transferTokensInfo)
    {
        bytes memory message = any2EvmMessage.data;
        bytes4 functionSelector = FunctionSelectorDecoder.decodeFunctionSelector(message);

        if (functionSelector == IStrategyManager.depositIntoStrategy.selector) {
            /// depositIntoStrategy - 0xe7a050aa
            _depositWithEigenAgent(message, any2EvmMessage.destTokenAmounts);

        } else if (functionSelector == IRestakingConnector.mintEigenAgent.selector) {
            /// mintEigenAgent - 0xcc15a557
            mintEigenAgent(message);

        } else if (functionSelector == IDelegationManager.queueWithdrawals.selector) {
            /// queueWithdrawals - 0x0dd8dd02
            _queueWithdrawalsWithEigenAgent(message);

        } else if (functionSelector == IDelegationManager.completeQueuedWithdrawal.selector) {
            /// completeWithdrawal - 0x60d7faed
            transferTokensInfo = _completeWithdrawalWithEigenAgent(message);

        } else if (functionSelector == IDelegationManager.delegateTo.selector) {
            /// delegateTo - 0xeea9064b
            _delegateToWithEigenAgent(message);

        } else if (functionSelector == IDelegationManager.undelegate.selector) {
            /// undelegate - 0xda8be864
            _undelegateWithEigenAgent(message);

        } else if (functionSelector == IRewardsCoordinator.processClaim.selector) {
            /// processClaim (Rewards) - 0x3ccc861d
            transferTokensInfo = _processClaimWithEigenAgent(message);

        } else {
            revert UnsupportedFunctionCall(functionSelector);
            // Should not reach this state with bridged funds, as SenderCCIP only sends funds for deposits.
        }
    }

    /**
     * @dev Manually mints an EigenAgent. Users can only own one EigenAgent at a time.
     * It will not mint a new EigenAgent if a user already has one.
     */
    function mintEigenAgent(bytes memory message) public override onlyReceiverCCIP {
        // Mint a EigenAgent manually, no signature required.
        address recipient = decodeMintEigenAgent(message);
        agentFactory.tryGetEigenAgentOrSpawn(recipient);
    }

    /**
     *
     *
     *                 Private Functions
     *
     *
     */

    /**
     * @dev Mints an EigenAgent before depositing into Eigenlayer if a user
     * does not already have one. Users can only own one EigenAgent at a time.
     * If the user already has an EigenAgent this call will continue depositing,
     * It will not mint a new EigenAgent if a user already has one.
     *
     * Errors with EigenAgentExecutionError(signer, expiry) error if there is an issue
     * retrieving an EigenAgent, spawning an EigenAgent, or depositing into Eigenlayer,
     * allowing the caller (ReceiverCCIP) to handle the error and refund the user if necessary.
     * @param messageWithSignature is the depositIntoSignature message with
     * appended signature for EigenAgent execution.
     */
    function _depositWithEigenAgent(
        bytes memory messageWithSignature,
        Client.EVMTokenAmount[] memory destTokenAmounts
    ) private {

        (
            // original message
            address _strategy,
            address token,
            uint256 amount,
            // message signature
            address signer, // original_staker
            uint256 expiry,
            bytes memory signature // signature from original_staker
        ) = decodeDepositIntoStrategyMsg(messageWithSignature);

        if (destTokenAmounts.length != 1) {
            // Eigenlayer DepositIntoStrategy deposits one token at a time, and SenderCCIP on L2
            // only sends one token at a time.
            // However it is possible to send multiple tokens with CCIP in other Sender implementations,
            // so revert with EigenAgentExecutionError to refund in case this happens.
            revert IRestakingConnector.EigenAgentExecutionError(
                signer,
                expiry,
                abi.encodeWithSelector(
                    TooManyTokensToDeposit.selector,
                    "DepositIntoStrategy only handles one token at a time"
                )
            );
        }

        // Validate token and amount in the CCIP message match the actual tokens received
        if (token != destTokenAmounts[0].token || amount != destTokenAmounts[0].amount) {
            revert IRestakingConnector.EigenAgentExecutionError(
                signer,
                expiry,
                abi.encodeWithSelector(
                    TokenAmountMismatch.selector,
                    "Token or amount in message does not match received tokens"
                )
            );
        }

        // Get original_staker's EigenAgent, or spawn one.
        try agentFactory.tryGetEigenAgentOrSpawn(signer) returns (IEigenAgent6551 eigenAgent) {

            // Token flow: ReceiverCCIP approves RestakingConnector to move tokens to EigenAgent,
            // then EigenAgent approves StrategyManager to move tokens into Eigenlayer
            eigenAgent.approveByWhitelistedContract(
                address(strategyManager),
                token,
                amount
            );

            // ReceiverCCIP approves RestakingConnector just before calling this function
            IERC20(token).safeTransferFrom(
                _receiverCCIP,
                address(eigenAgent),
                amount
            );

            try eigenAgent.executeWithSignature(
                address(strategyManager), // strategyManager
                0 ether,
                EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(_strategy, token, amount),
                expiry,
                signature
            ) returns (bytes memory result) {
                // success, do nothing.
            } catch (bytes memory err) {
                revert IRestakingConnector.EigenAgentExecutionError(signer, expiry, err);
            }

        } catch (bytes memory err) {
            revert IRestakingConnector.EigenAgentExecutionError(signer, expiry, err);
        }

    }

    /**
     * @dev Forwards a queueWithdrawals message to Eigenlayer to
     * the user's EigenAgent to execute on the user's behalf.
     * @param messageWithSignature is the queueWithdrawals message with
     * appended EigenAgent execution signature
     */
    function _queueWithdrawalsWithEigenAgent(bytes memory messageWithSignature) private {
        (
            // original message
            IDelegationManager.QueuedWithdrawalParams[] memory qwpArray,
            // message signature
            , // address __signer
            uint256 expiry,
            bytes memory signature
        ) = decodeQueueWithdrawalsMsg(messageWithSignature);

        // withdrawers are identical for every element in qwpArray[] because Eigenlayer requires:
        // msg.sender == withdrawer == staker for withdrawals (EigenAgent is all three)
        address withdrawer = qwpArray[0].withdrawer;
        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(withdrawer));

        uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(withdrawer);
        _withdrawalBlock[withdrawer][withdrawalNonce] = block.number;
        emit SetQueueWithdrawalBlock(withdrawer, withdrawalNonce, block.number);

        eigenAgent.executeWithSignature(
            address(delegationManager),
            0 ether,
            EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(qwpArray),
            expiry,
            signature
        );
    }

    struct PackedCompleteWithdrawalVars {
        IDelegationManager.Withdrawal withdrawal;
        IERC20[] tokensToWithdraw;
        uint256 middlewareTimesIndex;
        bool receiveAsTokens;
        address signer;
        uint256 expiry;
        bytes signature;
    }

    /**
     * @dev Forwards a completeWithdrawal message to Eigenlayer to the user's EigenAgent to execute.
     * @param messageWithSignature is the Eigenlayer processClaim message with
     * appended signature for EigenAgent to execute the message.
     * @return transferTokensInfo includes information on the following:
     * - transferTokensInfo.transferToAgentOwnerMessage encodes a "transferToAgentOwner" message to L2 to transfer
     *   withdrawn funds back to the EigenAgent's owner on L2.
     * - transferTokensInfo.transferRoot refers to the withdrawalTransferRoot commitment set in L2 contract
     *   when completeWithdrawal message was initially dispatched on L2. This ensures that the withdrawn
     *   funds to L2 will be transferred to the EigenAgent's owner and cannot be tampered with.
     * - transferTokensInfo.tokenAmounts is the token and amount withdrawn from Eigenlayer.
     */
    function _completeWithdrawalWithEigenAgent(bytes memory messageWithSignature)
        private
        returns (IRestakingConnector.TransferTokensInfo memory transferTokensInfo)
    {
        PackedCompleteWithdrawalVars memory vars = _decodeCompleteWithdrawalVarsPacked(messageWithSignature);

        // eigenAgent == withdrawer == staker == msg.sender (in Eigenlayer)
        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(vars.withdrawal.withdrawer));
        uint256[] memory balanceDiffsAmountsToBridge = new uint256[](vars.tokensToWithdraw.length);

        /// Vault shares != actual number of tokens received from Eigenlayer, so we need to
        /// Calculate balance differences before and after withdrawal
        /// to transfer from EigenAgent back to ReceiverCCIP after withdrawal.
        {
            uint256[] memory balancesBefore = _getEigenAgentBalancesWithdrawals(
                eigenAgent,
                vars.tokensToWithdraw
            );

            // (1) EigenAgent receives tokens from Eigenlayer, then
            // (2) approves RestakingConnector to (3) transfer tokens to ReceiverCCIP
            eigenAgent.executeWithSignature(
                address(delegationManager),
                0 ether,
                EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
                    vars.withdrawal,
                    vars.tokensToWithdraw,
                    vars.middlewareTimesIndex,
                    vars.receiveAsTokens
                ),
                vars.expiry,
                vars.signature
            );

            // Should have received tokens from StrategyManager, which
            // converts shares to tokens and transfers them to EigenAgent
            uint256[] memory balancesAfter = _getEigenAgentBalancesWithdrawals(
                eigenAgent,
                vars.tokensToWithdraw
            );

            for (uint256 i = 0; i < vars.tokensToWithdraw.length; ++i) {
                balanceDiffsAmountsToBridge[i] = balancesAfter[i] - balancesBefore[i];
            }
        }

        /// receiveAsTokens determines whether Eigenlayer returns tokens to the EigenAgent or
        /// re-deposits them into Eigenlayer strategy as part of a re-delegate and re-deposit flow.
        if (vars.receiveAsTokens) {

            // if receiveAsTokens == true, distribute tokens to user address on L1 and L2.
            // Otherwise if receiveAsTokens == false, withdrawal is redeposited in Eigenlayer
            // as shares, re-delegated to a new Operator as part of the `undelegate` flow.
            // We do not need to do anything in this case.

            address agentOwner = eigenAgent.owner();
            uint256 n; // tracks index of transferTokensArray (bridgeableTokens only)
            Client.EVMTokenAmount[] memory transferTokensArray = new Client.EVMTokenAmount[](
                _numBridgeableWithdrawalTokens(vars.tokensToWithdraw)
            );

            // If bridgeable, prepare a transferToAgentOwner message with transferRoots
            // calculate outside loop
            bytes32 withdrawalTransferRoot = EigenlayerMsgEncoders.calculateWithdrawalTransferRoot(
                delegationManager.calculateWithdrawalRoot(vars.withdrawal), // withdrawalRoot
                agentOwner // AgentOwner
            );

            for (uint256 i = 0; i < vars.tokensToWithdraw.length; ++i) {
                // (1) EigenAgent approves RestakingConnector to transfer tokens
                eigenAgent.approveByWhitelistedContract(
                    address(this), // restakingConnector
                    address(vars.tokensToWithdraw[i]),
                    balanceDiffsAmountsToBridge[i]
                );

                address tokenL2 = bridgeTokensL1toL2[address(vars.tokensToWithdraw[i])];

                if (tokenL2 == address(0)) {
                    // (2) If the token cannot bridge to L2, transfer to AgentOwner on L1.
                    // Shouldn't reach this state, unless user deposits L1 tokens via EigenAgent on L1.
                    IERC20(vars.tokensToWithdraw[i]).safeTransferFrom(
                        address(eigenAgent),
                        agentOwner, // AgentOwner
                        balanceDiffsAmountsToBridge[i]
                    );
                    emit SendingWithdrawalToAgentOwnerOnL1(
                        address(vars.tokensToWithdraw[i]),
                        agentOwner,
                        balanceDiffsAmountsToBridge[i]
                    );

                } else {

                    transferTokensArray[n] = Client.EVMTokenAmount({
                        amount: balanceDiffsAmountsToBridge[i],
                        token: address(vars.tokensToWithdraw[i])
                    });

                    ++n; // increment transferTokensArray index

                    // RestakingConnector transfers tokens to ReceiverCCIP to bridge
                    IERC20(vars.tokensToWithdraw[i]).safeTransferFrom(
                        address(eigenAgent),
                        _receiverCCIP,
                        balanceDiffsAmountsToBridge[i]
                    );
                }
            }

            transferTokensInfo.transferType = IRestakingConnector.TransferType.Withdrawal;
            transferTokensInfo.transferToAgentOwnerMessage = string(
                EigenlayerMsgEncoders.encodeTransferToAgentOwnerMsg(withdrawalTransferRoot)
            );
            transferTokensInfo.transferRoot = withdrawalTransferRoot;
            transferTokensInfo.tokenAmounts = transferTokensArray;
        }
    }

    /**
     * @dev Forwards a delegateTo message to Eigenlayer via EigenAgent to execute.
     * @param messageWithSignature is the Eigenlayer delegateTo message with
     * appended signature for EigenAgent to execute the message.
    */
    function _delegateToWithEigenAgent(bytes memory messageWithSignature) private {
        (
            // original message
            address operator,
            ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
            bytes32 approverSalt,
            // message signature
            address signer,
            uint256 expiry,
            bytes memory signature
        ) = DelegationDecoders.decodeDelegateToMsg(messageWithSignature);

        IEigenAgent6551 eigenAgent = agentFactory.getEigenAgent(signer);

        eigenAgent.executeWithSignature(
            address(delegationManager),
            0 ether,
            EigenlayerMsgEncoders.encodeDelegateTo(
                operator,
                approverSignatureAndExpiry,
                approverSalt
            ),
            expiry,
            signature
        );
    }

    /**
     * @dev Forwards a undelegate message to Eigenlayer via EigenAgent to execute.
     * @param messageWithSignature is the incoming Eigenlayer undelegate message with
     * appended signature for EigenAgent to execute the message.
    */
    function _undelegateWithEigenAgent(bytes memory messageWithSignature) private {
        (
            // original message
            address eigenAgentAddr, // staker in Eigenlayer delegating
            // message signature
            , // address __signer
            uint256 expiry,
            bytes memory signature
        ) = DelegationDecoders.decodeUndelegateMsg(messageWithSignature);

        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(eigenAgentAddr));

        uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(eigenAgentAddr);
        _withdrawalBlock[eigenAgentAddr][withdrawalNonce] = block.number;
        emit SetUndelegateBlock(eigenAgentAddr, withdrawalNonce, block.number);

        eigenAgent.executeWithSignature(
            address(delegationManager),
            0 ether,
            EigenlayerMsgEncoders.encodeUndelegateMsg(address(eigenAgent)),
            expiry,
            signature
        );
    }

    struct PackedRewardsClaimVars {
        IRewardsCoordinator.RewardsMerkleClaim claim;
        address recipient; // eigenAgent
        address signer;
        uint256 expiry;
        bytes signature;
    }

    /**
     * @dev Forwards a processClaim message to claim Eigenlayer rewards via EigenAgent.
     * @param messageWithSignature is the Eigenlayer processClaim message with
     * appended signature for EigenAgent to execute the message.
     * @return transferTokensInfo includes information on the following:
     * - transferTokensInfo.transferToAgentOwnerMessage encodes a "transferToAgentOwner" message
     *   to L2 to transfer rewards back to the EigenAgent's owner on L2.
     * - transferTokensInfo.transferRoot refers to the rewardsTransferRoot commitment set in L2
     *   contract when a processClaim message was initially sent on L2. This ensures that the rewards
     *   bridged to L2 will be transferred to the EigenAgent's owner and cannot be tampered with.
     * - transferTokensInfo.tokenAmounts is the token and amount of rewards claimed from Eigenlayer.
     */
    function _processClaimWithEigenAgent(bytes memory messageWithSignature)
        private
        returns (IRestakingConnector.TransferTokensInfo memory transferTokensInfo)
    {
        PackedRewardsClaimVars memory vars = _decodeRewardsClaimVarsPacked(messageWithSignature);
        uint256[] memory balanceDiffsAmountsToBridge = new uint256[](vars.claim.tokenLeaves.length);
        // eigenAgent == recipient == msg.sender (in Eigenlayer)
        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(vars.recipient));
        address agentOwner = eigenAgent.owner();

        // Vault shares != actual number of tokens received from Eigenlayer.
        // Calculate balances before and after claiming rewards and calculate differences
        {
            uint256[] memory balancesBefore = _getEigenAgentBalancesRewards(eigenAgent, vars.claim);

            // (1) EigenAgent receives tokens from Eigenlayer
            // then (2) approves RestakingConnector to (3) transfer tokens to ReceiverCCIP
            eigenAgent.executeWithSignature(
                address(rewardsCoordinator),
                0 ether,
                EigenlayerMsgEncoders.encodeProcessClaimMsg(vars.claim, vars.recipient),
                vars.expiry,
                vars.signature
            );

            // Should received tokens from StrategyManager now.
            // It converts shares to tokens and sends them to EigenAgent's balance
            uint256[] memory balancesAfter = _getEigenAgentBalancesRewards(eigenAgent, vars.claim);

            for (uint256 i = 0; i < vars.claim.tokenLeaves.length; ++i) {
                balanceDiffsAmountsToBridge[i] = balancesAfter[i] - balancesBefore[i];
            }
        }

        // The same rewardsRoot calculated on L2 in SenderHooks.sol
        // calculate before loop
        bytes32 rewardsTransferRoot = EigenlayerMsgEncoders.calculateRewardsTransferRoot(
            EigenlayerMsgEncoders.calculateRewardsRoot(vars.claim),
            agentOwner // AgentOwner
        );
        uint32 n; // tracks index of transferTokensArray (bridgeableTokens only)
        Client.EVMTokenAmount[] memory transferTokensArray = new Client.EVMTokenAmount[](
            _numBridgeableRewardsTokens(vars.claim.tokenLeaves)
        );

        for (uint32 i = 0; i < vars.claim.tokenLeaves.length; ++i) {

            uint256 rewardsAmount = balanceDiffsAmountsToBridge[i];
            address rewardsToken = address(vars.claim.tokenLeaves[i].token); // tokenL1

            // (1) EigenAgent approves RestakingConnector to transfer tokens to ReceiverCCIP
            eigenAgent.approveByWhitelistedContract(
                address(this), // restakingConnector
                rewardsToken,
                rewardsAmount
            );

            address tokenL2 = bridgeTokensL1toL2[rewardsToken];

            // Only transfer bridgeable tokens back to L2. Transfer remaining L1 tokens to AgentOwner.
            if (tokenL2 == address(0)) {
                // (2) If the token cannot be bridged to L2, transfer to AgentOwner on L1.
                IERC20(rewardsToken).safeTransferFrom(address(eigenAgent), agentOwner, rewardsAmount);
                emit SendingRewardsToAgentOwnerOnL1(rewardsToken, agentOwner, rewardsAmount);

            } else {
                // (2) RestakingConnector transfers tokens to ReceiverCCIP to bridge tokens
                IERC20(rewardsToken).safeTransferFrom(address(eigenAgent), _receiverCCIP, rewardsAmount);

                transferTokensArray[n] = Client.EVMTokenAmount({
                    token: rewardsToken,
                    amount: rewardsAmount
                });

                ++n; // increment index of transferTokensArray
            }
        }

        transferTokensInfo.transferType = IRestakingConnector.TransferType.RewardsClaim;
        transferTokensInfo.transferToAgentOwnerMessage = string(
            EigenlayerMsgEncoders.encodeTransferToAgentOwnerMsg(rewardsTransferRoot)
        );
        transferTokensInfo.transferRoot = rewardsTransferRoot;
        transferTokensInfo.tokenAmounts = transferTokensArray;
    }

    /**
     * @dev gets number of bridgeable tokens from an array that contains both bridgeable
     * and non-bridgeable tokens for withdrawals.
     */
    function _numBridgeableWithdrawalTokens(IERC20[] memory tokens) private view returns (uint256 num) {
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (bridgeTokensL1toL2[address(tokens[i])] != address(0)) {
                ++num;
            }
        }
    }

    function _numBridgeableRewardsTokens(IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves)
        private
        view
        returns (uint256 num)
    {
        for (uint256 i = 0; i < tokenLeaves.length; ++i) {
            if (bridgeTokensL1toL2[address(tokenLeaves[i].token)] != address(0)) {
                ++num;
            }
        }
    }

    function _decodeCompleteWithdrawalVarsPacked(bytes memory messageWithSignature)
        private
        pure
        returns (PackedCompleteWithdrawalVars memory vars)
    {
        (
            // original message
            IDelegationManager.Withdrawal memory withdrawal,
            IERC20[] memory tokensToWithdraw,
            uint256 middlewareTimesIndex,
            bool receiveAsTokens,
            // message signature
            address signer,
            uint256 expiry,
            bytes memory signature
        ) = decodeCompleteWithdrawalMsg(messageWithSignature);

        return PackedCompleteWithdrawalVars({
            withdrawal: withdrawal,
            tokensToWithdraw: tokensToWithdraw,
            middlewareTimesIndex: middlewareTimesIndex,
            receiveAsTokens: receiveAsTokens,
            signer: signer,
            expiry: expiry,
            signature: signature
        });
    }

    function _decodeRewardsClaimVarsPacked(bytes memory messageWithSignature)
        private
        pure
        returns (PackedRewardsClaimVars memory vars)
    {
        // struct RewardsMerkleClaim {
        //     uint32 rootIndex;
        //     uint32 earnerIndex;
        //     bytes earnerTreeProof;
        //     EarnerTreeMerkleLeaf earnerLeaf;
        //     uint32[] tokenIndices;
        //     bytes[] tokenTreeProofs;
        //     TokenTreeMerkleLeaf[] tokenLeaves;
        // }
        (
            IRewardsCoordinator.RewardsMerkleClaim memory claim,
            address recipient, // eigenAgent
            // message signature
            address signer,
            uint256 expiry,
            bytes memory signature
        ) = decodeProcessClaimMsg(messageWithSignature);

        return PackedRewardsClaimVars({
            claim: claim,
            recipient: recipient,
            signer: signer,
            expiry: expiry,
            signature: signature
        });
    }

    function _getEigenAgentBalancesWithdrawals(IEigenAgent6551 eigenAgent, IERC20[] memory tokensToWithdraw)
        private
        view
        returns (uint256[] memory)
    {
        uint256[] memory balances = new uint256[](tokensToWithdraw.length);
        for (uint256 i = 0; i < tokensToWithdraw.length; ++i) {
            balances[i] = tokensToWithdraw[i].balanceOf(address(eigenAgent));
        }
        return balances;
    }

    function _getEigenAgentBalancesRewards(
        IEigenAgent6551 eigenAgent,
        IRewardsCoordinator.RewardsMerkleClaim memory claim
    ) private view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](claim.tokenLeaves.length);
        for (uint256 i = 0; i < claim.tokenLeaves.length; ++i) {
            balances[i] = claim.tokenLeaves[i].token.balanceOf(address(eigenAgent));
        }
        return balances;
    }

}