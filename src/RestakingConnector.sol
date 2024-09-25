// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {ISignatureUtils} from "@eigenlayer-contracts/interfaces/ISignatureUtils.sol";

import {EigenlayerMsgDecoders, DelegationDecoders} from "./utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "./utils/EigenlayerMsgEncoders.sol";
import {Adminable} from "./utils/Adminable.sol";

import {IReceiverCCIP} from "./interfaces/IReceiverCCIP.sol";
import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";



contract RestakingConnector is
    Initializable,
    IRestakingConnector,
    EigenlayerMsgDecoders,
    Adminable
{

    IDelegationManager public delegationManager;
    IStrategyManager public strategyManager;
    IStrategy public strategy;
    address private _receiverCCIP;
    IAgentFactory public agentFactory;
    IRewardsCoordinator public rewardsCoordinator;

    mapping(address user => mapping(uint256 nonce => uint256 withdrawalBlock)) private _withdrawalBlock;
    mapping(bytes4 => uint256) internal _gasLimitsForFunctionSelectors;

    event SetQueueWithdrawalBlock(address indexed, uint256 indexed, uint256 indexed);
    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);
    event SendingRewardsToAgentOwnerOnL1(address indexed, address indexed, uint256 indexed);

    error AddressZero(string msg);

    /*
     *
     *                 Functions
     *
     *
     */

    constructor() {
        _disableInitializers();
    }

    function initialize(IAgentFactory newAgentFactory) external initializer {

        if (address(newAgentFactory) == address(0))
            revert AddressZero("AgentFactory cannot be address(0)");

        agentFactory = newAgentFactory;

        __Adminable_init();
    }

    modifier onlyReceiverCCIP() {
        require(msg.sender == _receiverCCIP, "not called by ReceiverCCIP");
        _;
    }

    function getReceiverCCIP() external view returns (address) {
        return _receiverCCIP;
    }

    /// @param newReceiverCCIP address of the ReceiverCCIP contract.
    function setReceiverCCIP(address newReceiverCCIP) external onlyOwner {
        _receiverCCIP = newReceiverCCIP;
    }

    function getAgentFactory() external view returns (address) {
        return address(agentFactory);
    }

    /// @param newAgentFactory address of the AgentFactory contract.
    function setAgentFactory(address newAgentFactory) external onlyOwner {
        if (newAgentFactory == address(0))
            revert AddressZero("AgentFactory cannot be address(0)");

        agentFactory = IAgentFactory(newAgentFactory);
    }

    function getEigenlayerContracts() external view returns (
        IDelegationManager,
        IStrategyManager,
        IStrategy,
        IRewardsCoordinator
    ) {
        return (delegationManager, strategyManager, strategy, rewardsCoordinator);
    }

    function setEigenlayerContracts(
        IDelegationManager _delegationManager,
        IStrategyManager _strategyManager,
        IStrategy _strategy,
        IRewardsCoordinator _rewardsCoordinator
    ) external onlyOwner {

        if (address(_delegationManager) == address(0))
            revert AddressZero("_delegationManager cannot be address(0)");

        if (address(_strategyManager) == address(0))
            revert AddressZero("_strategyManager cannot be address(0)");

        if (address(_strategy) == address(0))
            revert AddressZero("_strategy cannot be address(0)");

        if (address(_rewardsCoordinator) == address(0))
            revert AddressZero("_rewardsCoordinator cannot be address(0)");

        delegationManager = _delegationManager;
        strategyManager = _strategyManager;
        strategy = _strategy;
        rewardsCoordinator = _rewardsCoordinator;
    }

    /**
     * @dev Retrieves estimated gasLimits for different L2 restaking functions, e.g:
     * "handleTransferToAgentOwner(bytes)" == 0xd8a85b48
     * @param functionSelector bytes4 functionSelector to get estimated gasLimits for.
     * @return gasLimit a default gasLimit of 200_000 functionSelector parameter finds no matches.
     */
    function getGasLimitForFunctionSelector(bytes4 functionSelector)
        external
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
    ) external onlyAdminOrOwner {

        require(functionSelectors.length == gasLimits.length, "input arrays must have the same length");

        for (uint256 i = 0; i < gasLimits.length; ++i) {
            _gasLimitsForFunctionSelectors[functionSelectors[i]] = gasLimits[i];
            emit SetGasLimitForFunctionSelector(functionSelectors[i], gasLimits[i]);
        }
    }

    /**
     * @dev Retrieves the block.number where queueWithdrawal occured. Needed as the time when
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
     * @dev Mints an EigenAgent before depositing into Eigenlayer if a user
     * does not already have one. Users can only own one EigenAgent at a time.
     * If the user already has an EigenAgent this call will continue depositing,
     * It will not mint a new EigenAgent if a user already has one.
     *
     * Errors with EigenAgentExecutionError(signer, expiry) error if there is an issue
     * retrieving an EigenAgent, spawning an EigenAgent, or depositing into Eigenlayer,
     * allowing the caller (ReceiverCCIP) to handle the error and refund the user if necessary.
     */
    function depositWithEigenAgent(bytes memory messageWithSignature) external onlyReceiverCCIP {

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
     * @dev Manually mints an EigenAgent. Users can only own one EigenAgent at a time.
     * It will not mint a new EigenAgent if a user already has one.
     */
    function mintEigenAgent(bytes memory message) external onlyReceiverCCIP {
        // Mint a EigenAgent manually, no signature required.
        address recipient = decodeMintEigenAgent(message);
        agentFactory.tryGetEigenAgentOrSpawn(recipient);
    }

    /**
     * @dev Forwards a queueWithdrawals message to Eigenlayer to
     * the user's EigenAgent to execute on the user's behalf.
     */
    function queueWithdrawalsWithEigenAgent(bytes memory messageWithSignature) external onlyReceiverCCIP {
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
     * @return receiveAsTokens determines whether Eigenlayer returns tokens to the EigenAgent or
     * re-deposits them into Eigenlayer strategy vault as part of a re-delegate and re-deposit flow.
     * If receiveAsTokens is true, tokens are returned then the bridge will bridge the withdrawal
     * from L2 back to L1 to the EigenAgent's owner.
     * @param withdrawalAmount is the amount withdrawn from Eigenlayer
     * @param withdrawalToken is the token withdrawn from Eigenlayer. Must be bridgeable or reverts.
     * @param messageForL2 encodes a "transferToAgentOwner" message to L2 to transfer the withdrawn
     * funds back to the EigenAgent's owner.
     * @param withdrawalTransferRoot refers to the withdrawalTransferRoot commitment set in L2 contract
     * when completeWithdrawal message was initially dispatched on L2. This ensures that the withdrawn
     * funds to L2 will be transferred to the EigenAgent's owner and cannot be tampered with.
     */
    function completeWithdrawalWithEigenAgent(bytes memory messageWithSignature)
        external
        onlyReceiverCCIP
        returns (
            bool receiveAsTokens,
            string memory messageForL2,
            bytes32 withdrawalTransferRoot,
            address withdrawalToken,
            uint256 withdrawalAmount
        )
    {
        // scope to reduce variable count
        {
            (
                // original message
                IDelegationManager.Withdrawal memory withdrawal,
                IERC20[] memory tokensToWithdraw,
                uint256 middlewareTimesIndex,
                bool _receiveAsTokens,
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
                    _receiveAsTokens
                ),
                expiry,
                signature
            );

            // bridgeable token's L1 address
            address bridgeTokenL1 = IReceiverCCIP(_receiverCCIP).bridgeTokenL1();

            for (uint256 i = 0; i < tokensToWithdraw.length; ++i) {

                // (1) EigenAgent approves RestakingConnector to transfer tokens to ReceiverCCIP
                eigenAgent.approveByWhitelistedContract(
                    address(this), // restakingConnector
                    address(tokensToWithdraw[i]),
                    withdrawal.shares[i]
                );

                if (address(tokensToWithdraw[i]) != bridgeTokenL1) {
                    // (2) If the token cannot bridge to L2, transfer to AgentOwner on L1.
                    // Should not reach this state, unless user manually uses EigenAgent on L1 to deposit arbitrary tokens.
                    IERC20(tokensToWithdraw[i]).transferFrom(
                        address(eigenAgent),
                        signer, // AgentOwner
                        withdrawal.shares[i]
                    );

                } else {
                    // At most only 1 token reaches this state (only 1 BridgeToken)
                    // Set return variables defined in the function signature.
                    receiveAsTokens = _receiveAsTokens;
                    withdrawalToken = address(tokensToWithdraw[i]);
                    withdrawalAmount = withdrawal.shares[i];
                    withdrawalTransferRoot = EigenlayerMsgEncoders.calculateWithdrawalTransferRoot(
                        delegationManager.calculateWithdrawalRoot(withdrawal), // withdrawalRoot
                        withdrawalAmount,
                        signer
                    );
                    messageForL2 = string(EigenlayerMsgEncoders.encodeTransferToAgentOwnerMsg(
                        withdrawalTransferRoot
                    ));

                    // (3) RestakingConnector transfers tokens to ReceiverCCIP, to send tokens to CCIP Router
                    if (_receiveAsTokens) {
                        IERC20(withdrawalToken).transferFrom(
                            address(eigenAgent),
                            _receiverCCIP,
                            withdrawalAmount
                        );
                    }
                }
            }
        }
        // return variables defined in the function signature.
        // return (
        //     receiveAsTokens,
        //     messageForL2,
        //     withdrawalTransferRoot,
        //     withdrawalToken,
        //     withdrawalAmount
        // );
    }

    /// @dev Forwards a delegateTo message to Eigenlayer via the user's EigenAgent.
    function delegateToWithEigenAgent(bytes memory messageWithSignature) external onlyReceiverCCIP {
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

    /// @dev Forwards a undelegate message to Eigenlayer via EigenAgent to execute.
    function undelegateWithEigenAgent(bytes memory messageWithSignature) external onlyReceiverCCIP {
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

    /// @dev Forwards a processClaim message to claim Eigenlayer rewards via EigenAgent.
    function processClaimWithEigenAgent(bytes memory messageWithSignature)
        external
        onlyReceiverCCIP
        returns (
            string memory messageForL2,
            bytes32 rewardsTransferRoot,
            address rewardsToken,
            uint256 rewardsAmount
        )
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
        // bridgeable token's L1 address
        address bridgeTokenL1 = IReceiverCCIP(_receiverCCIP).bridgeTokenL1();

        for (uint32 i = 0; i < claim.tokenLeaves.length; ++i) {

            uint256 _rewardsAmount = claim.tokenLeaves[i].cumulativeEarnings;
            address _rewardsToken = address(claim.tokenLeaves[i].token);

            // (1) EigenAgent approves RestakingConnector to transfer tokens to ReceiverCCIP
            eigenAgent.approveByWhitelistedContract(
                address(this), // restakingConnector
                _rewardsToken,
                _rewardsAmount
            );

            // Only transfer bridgeable tokens back to L2. Transfer remaining L1 tokens to AgentOwner.
            if (_rewardsToken != bridgeTokenL1) {
                // (2) If the token is L1-native and cannot be bridged to L2, transfer to AgentOwner on L1.
                IERC20(_rewardsToken).transferFrom(
                    address(eigenAgent),
                    signer, // AgentOwner
                    _rewardsAmount
                );

                emit SendingRewardsToAgentOwnerOnL1(
                    _rewardsToken,
                    signer, // AgentOwner
                    _rewardsAmount
                );

            } else {
                // (2) RestakingConnector transfers tokens to ReceiverCCIP to bridge tokens
                IERC20(_rewardsToken).transferFrom(
                    address(eigenAgent),
                    _receiverCCIP,
                    _rewardsAmount
                );

                // return variables
                rewardsToken = _rewardsToken;
                rewardsAmount = _rewardsAmount;
                rewardsTransferRoot = EigenlayerMsgEncoders.calculateRewardsTransferRoot(
                    rewardsRoot,
                    rewardsAmount,
                    rewardsToken,
                    signer // AgentOwner
                );
                // rewardsTransferRoot for L2 transfer
                messageForL2 = string(EigenlayerMsgEncoders.encodeTransferToAgentOwnerMsg(
                    rewardsTransferRoot
                ));
            }
        }
    }
}