// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    event SendingRewardsToAgentOwnerOnL1(address indexed, address indexed, uint256 indexed);
    event SetQueueWithdrawalBlock(address indexed, uint256 indexed, uint256 indexed);

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
     * @dev This function only called by ReceiverCCIP.
     * @notice This function matches a function selector, then forwards CCIP Eigenlayer messages
     * to the RestakingConnector which deserializes the rest of the message and
     * forwards it to the user's EigenAgent for execution.
     * @param any2EvmMessage is the message the CCIP bridge receives and forwards to this function
     * @return transferTokensArray returns an array of structs containing info for the bridge contract
     * to bridge withdrawals or rewards back to L2, and transfer the funds to the AgentOwner on L2.
     */
    function dispatchMessageToEigenAgent(Client.Any2EVMMessage memory any2EvmMessage)
        external
        override
        onlyReceiverCCIP
        returns (IRestakingConnector.TransferTokensInfo[] memory transferTokensArray)
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
            transferTokensArray = _completeWithdrawalWithEigenAgent(message);

        } else if (functionSelector == IDelegationManager.delegateTo.selector) {
            /// delegateTo - 0xeea9064b
            _delegateToWithEigenAgent(message);

        } else if (functionSelector == IDelegationManager.undelegate.selector) {
            /// undelegate - 0xda8be864
            _undelegateWithEigenAgent(message);

        } else if (functionSelector == IRewardsCoordinator.processClaim.selector) {
            /// processClaim (Rewards) - 0x3ccc861d
            transferTokensArray = _processClaimWithEigenAgent(message);
        }
        // Should not reach this state with bridged funds, as SenderCCIP only sends funds for deposits.
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

        if (destTokenAmounts.length > 1) {
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
            IERC20(token).transferFrom(
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
            , // address signer
            uint256 expiry,
            bytes memory signature
        ) = decodeQueueWithdrawalsMsg(messageWithSignature);

        // withdrawers are identical for every element in qwpArray[] because Eigenlayer requires:
        // msg.sender == withdrawer == staker for withdrawals (EigenAgent is all three)
        address withdrawer = qwpArray[0].withdrawer;
        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(withdrawer));

        uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(withdrawer);
        _withdrawalBlock[withdrawer][withdrawalNonce] = block.number;

        eigenAgent.executeWithSignature(
            address(delegationManager),
            0 ether,
            EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(qwpArray),
            expiry,
            signature
        );
    }

    /**
     * @dev Forwards a completeWithdrawal message to Eigenlayer to the user's EigenAgent to execute.
     * @param messageWithSignature is the Eigenlayer processClaim message with
     * appended signature for EigenAgent to execute the message.
     * @return transferTokensArray is an array of TransferTokensInfo objects that include information on
     * the following:
     * - transferTokensArray.transferToAgentOwnerMessage encodes a "transferToAgentOwner" message to L2 to transfer
     * withdrawn funds back to the EigenAgent's owner on L2.
     * - transferTokensArray.transferRoot refers to the withdrawalTransferRoot commitment set in L2 contract
     * when completeWithdrawal message was initially dispatched on L2. This ensures that the withdrawn
     * funds to L2 will be transferred to the EigenAgent's owner and cannot be tampered with.
     * - transferTokensArray.transferToken is the token withdrawn from Eigenlayer. Must be bridgeable or reverts.
     * - transferTokensArray.transferAmount is the amount withdrawn from Eigenlayer
     */
    function _completeWithdrawalWithEigenAgent(bytes memory messageWithSignature)
        private
        returns (IRestakingConnector.TransferTokensInfo[] memory transferTokensArray)
    {
        // scope to reduce variable count
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

            // eigenAgent == withdrawer == staker == msg.sender (in Eigenlayer)
            IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(withdrawal.withdrawer));

            // (1) EigenAgent receives tokens from Eigenlayer
            // then (2) approves RestakingConnector to (3) transfer tokens to ReceiverCCIP
            eigenAgent.executeWithSignature(
                address(delegationManager),
                0 ether,
                EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
                    withdrawal,
                    tokensToWithdraw,
                    middlewareTimesIndex,
                    receiveAsTokens
                ),
                expiry,
                signature
            );

            uint256 n; // tracks index of transferTokensArray (bridgeableTokens only)
            // instantiate array size
            transferTokensArray = new IRestakingConnector.TransferTokensInfo[](
                _numBridgeableTokens(tokensToWithdraw)
            );

            /// receiveAsTokens determines whether Eigenlayer returns tokens to the EigenAgent or
            /// re-deposits them into Eigenlayer strategy as part of a re-delegate and re-deposit flow.
            if (receiveAsTokens) {
                // if receiveAsTokens == true, distribute tokens to user address on L1 and L2.
                // Otherwise if receiveAsTokens == false, withdrawal is redeposited in Eigenlayer
                // as shares, re-delegated to a new Operator as part of the `undelegate` flow.
                // We do not need to do anything in this case.
                for (uint256 i = 0; i < tokensToWithdraw.length; ++i) {

                    // (1) EigenAgent approves RestakingConnector to transfer tokens
                    eigenAgent.approveByWhitelistedContract(
                        address(this), // restakingConnector
                        address(tokensToWithdraw[i]),
                        withdrawal.shares[i]
                    );

                    address tokenL2 = bridgeTokensL1toL2[address(tokensToWithdraw[i])];

                    if (tokenL2 == address(0)) {
                        // (2) If the token cannot bridge to L2, transfer to AgentOwner on L1.
                        // Shouldn't reach this state, unless user deposits L1 tokens via EigenAgent on L1.
                        IERC20(tokensToWithdraw[i]).transferFrom(
                            address(eigenAgent),
                            signer, // AgentOwner
                            withdrawal.shares[i]
                        );

                    } else {

                        // (3) If bridgeable, prepare a transferToAgentOwner message with transferRoots
                        bytes32 withdrawalTransferRoot = EigenlayerMsgEncoders.calculateWithdrawalTransferRoot(
                            delegationManager.calculateWithdrawalRoot(withdrawal), // withdrawalRoot
                            signer
                        );

                        transferTokensArray[n] = IRestakingConnector.TransferTokensInfo({
                            transferType: IRestakingConnector.TransferType.Withdrawal,
                            transferToAgentOwnerMessage: string(
                                EigenlayerMsgEncoders.encodeTransferToAgentOwnerMsg(withdrawalTransferRoot)
                            ),
                            transferRoot: withdrawalTransferRoot,
                            transferAmount: withdrawal.shares[i],
                            transferToken: address(tokensToWithdraw[i])
                        });

                        ++n; // increment transferTokens index after setting transferTokensArray

                        // RestakingConnector transfers tokens to ReceiverCCIP to bridge
                        IERC20(tokensToWithdraw[i]).transferFrom(
                            address(eigenAgent),
                            _receiverCCIP,
                            withdrawal.shares[i] // withdrawalAmount
                        );
                    }
                }
            }
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
            , // address signer
            uint256 expiry,
            bytes memory signature
        ) = DelegationDecoders.decodeUndelegateMsg(messageWithSignature);

        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(eigenAgentAddr));

        uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(eigenAgentAddr);

        _withdrawalBlock[eigenAgentAddr][withdrawalNonce] = block.number;

        eigenAgent.executeWithSignature(
            address(delegationManager),
            0 ether,
            EigenlayerMsgEncoders.encodeUndelegateMsg(address(eigenAgent)),
            expiry,
            signature
        );
    }

    /**
     * @dev Forwards a processClaim message to claim Eigenlayer rewards via EigenAgent.
     * @param messageWithSignature is the Eigenlayer processClaim message with
     * appended signature for EigenAgent to execute the message.
     * @return transferTokensArray is an array of objects that include information such as:
     * - transferTokensArray.transferToAgentOwnerMessage encodes a "transferToAgentOwner" message
     * to L2 to transfer rewards back to the EigenAgent's owner on L2.
     * - transferTokensArray.transferRoot refers to the rewardsTransferRoot commitment set in L2
     * contract when a processClaim message was initially sent on L2. This ensures that the rewards
     * bridged to L2 will be transferred to the EigenAgent's owner and cannot be tampered with.
     * - transferTokensArray.transferToken is the token reward claimed from Eigenlayer.
     * - transferTokensArray.transferAmount is the amount of token rewards claimed from Eigenlayer.
     */
    function _processClaimWithEigenAgent(bytes memory messageWithSignature)
        private
        returns (IRestakingConnector.TransferTokensInfo[] memory transferTokensArray)
    {
        IRewardsCoordinator.RewardsMerkleClaim memory claim;
        address signer;
        IEigenAgent6551 eigenAgent;
        // scope to reduce variable count
        {
            (
                // original message
                IRewardsCoordinator.RewardsMerkleClaim memory _claim,
                address recipient, // eigenAgent
                // message signature
                address _signer,
                uint256 expiry,
                bytes memory signature
            ) = decodeProcessClaimMsg(messageWithSignature);

            // eigenAgent == recipient == msg.sender (in Eigenlayer)
            IEigenAgent6551 _eigenAgent = IEigenAgent6551(payable(recipient));

            claim = _claim;
            signer = _signer;
            eigenAgent = _eigenAgent;

            eigenAgent.executeWithSignature(
                address(rewardsCoordinator),
                0 ether,
                EigenlayerMsgEncoders.encodeProcessClaimMsg(claim, recipient),
                expiry,
                signature
            );
        }

        // The same rewardsRoot calculated on L2 in SenderHooks.sol
        bytes32 rewardsRoot = EigenlayerMsgEncoders.calculateRewardsRoot(claim);
        uint32 n; // tracks index of transferTokensArray (bridgeableTokens only)

        transferTokensArray = new IRestakingConnector.TransferTokensInfo[](claim.tokenLeaves.length);

        for (uint32 i = 0; i < claim.tokenLeaves.length; ++i) {

            uint256 rewardsAmount = claim.tokenLeaves[i].cumulativeEarnings;
            address rewardsToken = address(claim.tokenLeaves[i].token); // tokenL1

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
                IERC20(rewardsToken).transferFrom(address(eigenAgent), signer, rewardsAmount);
                // signer is AgentOwner
                emit SendingRewardsToAgentOwnerOnL1(rewardsToken, signer, rewardsAmount);

            } else {
                // (2) RestakingConnector transfers tokens to ReceiverCCIP to bridge tokens
                IERC20(rewardsToken).transferFrom(address(eigenAgent), _receiverCCIP, rewardsAmount);

                bytes32 rewardsTransferRoot = EigenlayerMsgEncoders.calculateRewardsTransferRoot(
                    rewardsRoot,
                    signer // AgentOwner
                );

                transferTokensArray[n] = IRestakingConnector.TransferTokensInfo({
                    transferType: IRestakingConnector.TransferType.RewardsClaim,
                    transferToAgentOwnerMessage: string(
                        EigenlayerMsgEncoders.encodeTransferToAgentOwnerMsg(rewardsTransferRoot)
                    ),
                    transferRoot: rewardsTransferRoot,
                    transferToken: rewardsToken,
                    transferAmount: rewardsAmount
                });

                ++n; // increment index after assigning transferTokensInfo
            }
        }
    }

    /**
     * @dev gets number of bridgeable tokens from an array that contains both bridgeable
     * and non-bridgeable tokens for withdrawals.
     */
    function _numBridgeableTokens(IERC20[] memory tokens) private view returns (uint256 num) {
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (bridgeTokensL1toL2[address(tokens[i])] != address(0)) {
                ++num;
            }
        }
    }

}