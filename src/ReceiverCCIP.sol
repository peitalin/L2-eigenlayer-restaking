// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {FunctionSelectorDecoder} from "./utils/FunctionSelectorDecoder.sol";
import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {ISenderCCIP} from "./interfaces/ISenderCCIP.sol";
import {BaseMessengerCCIP} from "./BaseMessengerCCIP.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";


/// @title ETH L1 Messenger Contract: receives Eigenlayer messages from L2 and processes them
contract ReceiverCCIP is Initializable, BaseMessengerCCIP {

    IRestakingConnector public restakingConnector;
    address public senderContractL2;
    mapping(bytes32 messageId => uint256) public amountRefundedToMessageIds;

    event BridgingWithdrawalToL2(
        bytes32 indexed withdrawalTransferRoot,
        address indexed withdrawalToken,
        uint256 indexed withdrawalAmount
    );

    event BridgingRewardsToL2(
        bytes32 indexed rewardsTransferRoot,
        address indexed rewardsToken,
        uint256 indexed rewardsAmount
    );

    event RefundingDeposit(
        address indexed signer,
        address indexed token,
        uint256 indexed amount
    );

    event UpdatedAmountRefunded(
        bytes32 indexed messageId,
        uint256 indexed beforeAmount,
        uint256 indexed afterAmount
    );

    error AddressZero(string msg);
    error AgentCallError(string errorMsg, bytes customErr);

    /// @param _router address of the router contract.
    /// @param _link address of the link contract.
    constructor(address _router, address _link) BaseMessengerCCIP(_router, _link) {
        _disableInitializers();
    }

    /// @param _restakingConnector address of the restakingConnector contract.
    /// @param _senderContractL2 address of the senderCCIP contract on L2
    function initialize(
        IRestakingConnector _restakingConnector,
        ISenderCCIP _senderContractL2
    ) external initializer {

        if (address(_restakingConnector) == address(0))
            revert AddressZero("RestakingConnector cannot be address(0)");

        if (address(_senderContractL2) == address(0))
            revert AddressZero("SenderCCIP cannot be address(0)");

        restakingConnector = _restakingConnector;
        senderContractL2 = address(_senderContractL2);

        BaseMessengerCCIP.__BaseMessengerCCIP_init();
    }

    function getSenderContractL2Addr() external view returns (address) {
        return senderContractL2;
    }

    function setSenderContractL2Addr(address _senderContractL2) external onlyOwner {
        if (address(_senderContractL2) == address(0))
            revert AddressZero("SenderContract on L2 cannot be address(0)");

        senderContractL2 = _senderContractL2;
    }

    function getRestakingConnector() external view returns (IRestakingConnector) {
        return restakingConnector;
    }

    function setRestakingConnector(IRestakingConnector _restakingConnector) external onlyOwner {
        if (address(_restakingConnector) == address(0))
            revert AddressZero("RestakingConnector cannot be address(0)");

        restakingConnector = _restakingConnector;
    }

    /// @dev Gets the amount refunded to prevent triggering a refund if admin manually refunds user.
    /// @param messageId is the CCIP messageId
    /// @return amount refunded
    function amountRefunded(bytes32 messageId) external view returns (uint256) {
        return amountRefundedToMessageIds[messageId];
    }

    /// @dev This function sets amount refunded in case owner wants to refund a user manually.
    /// @param messageId is the CCIP messageId
    /// @param amountAfter is the amount refunded
    function setAmountRefundedToMessageId(bytes32 messageId, uint256 amountAfter) external onlyOwner {
        uint256 amountBefore = amountRefundedToMessageIds[messageId];
        amountRefundedToMessageIds[messageId] = amountAfter;
        emit UpdatedAmountRefunded(messageId, amountBefore, amountAfter);
    }

    /*
     *
     *                Receiving
     *
     *
    */

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address))
        )
    {
        s_lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        s_lastReceivedText = abi.decode(any2EvmMessage.data, (string)); // abi-decoding of the sent text
        if (any2EvmMessage.destTokenAmounts.length > 0) {
            s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
            s_lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;
        } else {
            s_lastReceivedTokenAddress = address(0);
            s_lastReceivedTokenAmount = 0;
        }

        try this.dispatchMessageToEigenAgent(
            any2EvmMessage,
            s_lastReceivedTokenAddress,
            s_lastReceivedTokenAmount
        ) returns (string memory textMsg) {
            // EigenAgent executes message successfully.
            emit MessageReceived(
                any2EvmMessage.messageId,
                any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
                abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
                textMsg,
                s_lastReceivedTokenAddress,
                s_lastReceivedTokenAmount
            );

        } catch (bytes memory customError) {

            bytes4 errorSelector = FunctionSelectorDecoder.decodeErrorSelector(customError);
            // Decode and try catch the EigenAgentExecutionError

            if (errorSelector == IRestakingConnector.EigenAgentExecutionError.selector) {
                // If there were bridged tokens (e.g. DepositIntoStrategy call)...
                // and the deposit has not been manually refunded by an admin...
                if (
                    s_lastReceivedTokenAmount > 0 &&
                    s_lastReceivedTokenAddress != address(0) &&
                    amountRefundedToMessageIds[any2EvmMessage.messageId] <= 0
                ) {
                    // ...mark messageId as refunded
                    amountRefundedToMessageIds[any2EvmMessage.messageId] = s_lastReceivedTokenAmount;
                    // ...then initiate a refund back to L2
                    return _refundToSignerAfterExpiry(customError);

                } else {
                    // Parse EigenAgentExecutionError message and continue allowing manual re-execution tries.
                    (
                        address signer,
                        uint256 expiry,
                        string memory errStr
                    ) = FunctionSelectorDecoder.decodeEigenAgentExecutionError(customError);

                    revert IRestakingConnector.EigenAgentExecutionErrorStr(signer, expiry, errStr);
                }
            } else {
                // For other errors revert and try parse error message
                revert(string(customError));
            }
        }
    }

    /**
     * @dev This function is called only by this contract (marked external for try/catch feature).
     * @notice This function matches the on function selector, then forwards CCIP messages for
     * Eigenlayer to the RestakingConnector which will deserialize the rest of the message and
     * forward it to the user's EigenAgent for execution.
     */
    function dispatchMessageToEigenAgent(
        Client.Any2EVMMessage memory any2EvmMessage,
        address token,
        uint256 amount
    ) external returns (string memory textMsg) {

        require(msg.sender == address(this), "Function not called internally");

        bytes memory message = any2EvmMessage.data;
        bytes4 functionSelector = FunctionSelectorDecoder.decodeFunctionSelector(message);
        textMsg = "no matching Eigenlayer function selector";

        /// Deposit Into Strategy
        if (functionSelector == IStrategyManager.depositIntoStrategy.selector) {
            // cast sig "depositIntoStrategy(address,address,uint256)" == 0xe7a050aa
            IERC20(token).approve(address(restakingConnector), amount);
            // approve RestakingConnector to transfer tokens to EigenAgent
            restakingConnector.depositWithEigenAgent(message);
            textMsg = "Deposited by EigenAgent";
        }

        /// Mint EigenAgent
        if (functionSelector == IRestakingConnector.mintEigenAgent.selector) {
            // cast sig "mintEigenAgent(bytes)" == 0xcc15a557
            restakingConnector.mintEigenAgent(message);
            textMsg = "called mintEigenAgent";
        }

        /// Queue Withdrawals
        if (functionSelector == IDelegationManager.queueWithdrawals.selector) {
            // cast sig "queueWithdrawals((address[],uint256[],address)[])" == 0x0dd8dd02
            restakingConnector.queueWithdrawalsWithEigenAgent(message);
            textMsg = "Withdrawal queued by EigenAgent";
        }

        /// Complete Withdrawal
        if (functionSelector == IDelegationManager.completeQueuedWithdrawal.selector) {
            // cast sig "completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],uint256,bool)" == 0x60d7faed
            (
                bool receiveAsTokens,
                string memory messageForL2,
                bytes32 withdrawalTransferRoot,
                address withdrawalToken,
                uint256 withdrawalAmount
            ) = restakingConnector.completeWithdrawalWithEigenAgent(message);

            if (receiveAsTokens) {
                /// if `receiveAsTokens == true`, ReceiverCCIP should have received tokens
                /// back from EigenAgent after completeWithdrawal.
                ///
                /// Send handleTransferToAgentOwner message to bridge tokens back to L2.
                /// L2 SenderCCIP transfers tokens to AgentOwner.
                this.sendMessagePayNative(
                    BaseSepolia.ChainSelector, // destination chain
                    senderContractL2,
                    messageForL2,
                    withdrawalToken, // L1 token to burn/lock
                    withdrawalAmount,
                    0 // use default gasLimit
                );

                emit BridgingWithdrawalToL2(
                    withdrawalTransferRoot,
                    withdrawalToken,
                    withdrawalAmount
                );

                textMsg = "Complete Queued Withdrawal by EigenAgent";
            } else {
                /// Otherwise if `receiveAsTokens == false`, withdrawal is redeposited in Eigenlayer
                /// as shares, re-delegated to a new Operator as part of the `undelegate` flow.
                /// We do not need to do anything in this case.
            }
        }

        /// Delegate To
        if (functionSelector == IDelegationManager.delegateTo.selector) {
            restakingConnector.delegateToWithEigenAgent(message);
            textMsg = "Delegated to Operator by EigenAgent";
        }

        /// Undelegate
        if (functionSelector == IDelegationManager.undelegate.selector) {
            restakingConnector.undelegateWithEigenAgent(message);
            textMsg = "Undelegated by EigenAgent";
        }

        /// Process Claim (Rewards)
        if (functionSelector == IRewardsCoordinator.processClaim.selector) {
            (
                string memory messageForL2,
                bytes32 rewardsTransferRoot,
                address rewardsToken,
                uint256 rewardsAmount
            ) = restakingConnector.processClaimWithEigenAgent(message);

            if (rewardsToken == EthSepolia.BridgeToken) {

                this.sendMessagePayNative(
                    BaseSepolia.ChainSelector, // destination chain
                    senderContractL2,
                    messageForL2,
                    rewardsToken, // L1 token to burn/lock
                    rewardsAmount,
                    0 // use default gasLimit
                );

                emit BridgingRewardsToL2(
                    rewardsTransferRoot,
                    rewardsToken,
                    rewardsAmount
                );
            }

            textMsg = "Claiming Rewards with EigenAgent";
        }
    }

    /**
     * @dev Allows users to manually execute EigenAgent execution messages until expiry
     * if the message fails because of gas spikes, or other temporary issues.
     *
     * After message expiry, manual executions that result in a EigenAgentExecutionError will
     * trigger a refund to the original sender back on L2. This may happen for instance if an
     * Operator goes offline when attempting to deposit.
     *
     * No other Eigenlayer function call bridges tokens, this is the main UX edgecase to cover.
     */
    function _refundToSignerAfterExpiry(bytes memory customError) private {

        (
            address signer,
            uint256 expiry,
            string memory errStr
        ) = FunctionSelectorDecoder.decodeEigenAgentExecutionError(customError);

        if (block.timestamp > expiry) {
            // If message has expired, trigger CCIP call to bridge funds back to L2 signer
            this.sendMessagePayNative(
                BaseSepolia.ChainSelector, // destination chain
                signer, // receiver on L2
                string.concat(errStr, ": refunding to L2 signer"),
                s_lastReceivedTokenAddress, // L1 token to burn/lock
                s_lastReceivedTokenAmount,
                0 // use default gasLimit for this call
            );

            emit RefundingDeposit(signer, s_lastReceivedTokenAddress, s_lastReceivedTokenAmount);

        } else {
            // otherwise if message hasn't expired, allow manual execution retries
            revert IRestakingConnector.ExecutionErrorRefundAfterExpiry(
                errStr,
                "Manually execute to refund after timestamp:",
                expiry
            );
        }
    }

    /*
     *
     *                Sending
     *
     *
    */

    /**
     * @param _receiver The address of the receiver.
     * @param _text The string data to be sent.
     * @param _token The token to be transferred.
     * @param _amount The amount of the token to be transferred.
     * @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
     * @param _overrideGasLimit set the gaslimit manually. If 0, uses default gasLimits.
     * @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
     */
    function _buildCCIPMessage(
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
        address _feeTokenAddress,
        uint256 _overrideGasLimit
    ) internal override returns (Client.EVM2AnyMessage memory) {

        Client.EVMTokenAmount[] memory tokenAmounts;
        if (_amount <= 0) {
            // Must be an empty array as no tokens are transferred
            // non-empty arrays with 0 amounts error with CannotSendZeroTokens() == 0x5cf04449
            tokenAmounts = new Client.EVMTokenAmount[](0);
        } else {
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: _token,
                amount: _amount
            });
        }

        bytes memory message = abi.encode(_text);

        bytes4 functionSelector = FunctionSelectorDecoder.decodeFunctionSelector(message);

        uint256 gasLimit = restakingConnector.getGasLimitForFunctionSelector(functionSelector);
        if (_overrideGasLimit > 0) {
            gasLimit = _overrideGasLimit;
        }

        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver),
                data: message,
                tokenAmounts: tokenAmounts,
                feeToken: _feeTokenAddress,
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV1({ gasLimit: gasLimit })
                )
            });
    }

}

