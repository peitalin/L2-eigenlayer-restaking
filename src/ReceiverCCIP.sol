// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";

import {FunctionSelectorDecoder} from "./utils/FunctionSelectorDecoder.sol";
import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {ISenderCCIP} from "./interfaces/ISenderCCIP.sol";
import {BaseMessengerCCIP} from "./BaseMessengerCCIP.sol";
import {BaseSepolia} from "../script/Addresses.sol";


/// @title ETH L1 Messenger Contract: receives messages from L2 and processes them
contract ReceiverCCIP is Initializable, BaseMessengerCCIP {
    using SafeERC20 for IERC20;

    IRestakingConnector public restakingConnector;
    address public senderContractL2;

    mapping(bytes32 messageId => mapping(address token => uint256 amount)) public amountRefundedToMessageIds;

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
        address indexed token,
        uint256 beforeAmount,
        uint256 indexed afterAmount
    );

    error AddressZero(string msg);
    error AlreadyRefunded(uint256 amount);

    /// @param _router address of the router contract.
    constructor(address _router) BaseMessengerCCIP(_router) {
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

    function getSenderContractL2() external view returns (address) {
        return senderContractL2;
    }

    function setSenderContractL2(address _senderContractL2) external onlyOwner {
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

    /**
     * @dev Looks up the amount refunded for a messageId.
     * @param messageId is the CCIP messageId.
     * @return amount is the amount refunded.
     */
    function amountRefunded(bytes32 messageId, address token) external view returns (uint256) {
        return amountRefundedToMessageIds[messageId][token];
    }

    /**
     * @notice Lets admin withdraw tokens and mark that messageId as refunded, preventing further refunds.
     * @param messageId is the CCIP messageId.
     * @param beneficiary address to which the tokens will be sent.
     * @param token contract address of the ERC20 token to be withdrawn.
     * @param amount The amount to withdraw.
     */
    function withdrawTokenForMessageId(
        bytes32 messageId,
        address beneficiary,
        address token,
        uint256 amount
    ) external onlyOwner {

        uint256 amountBefore = amountRefundedToMessageIds[messageId][token];
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));

        if (amountBefore > 0) revert AlreadyRefunded(amountBefore);
        if (amount > tokenBalance) revert WithdrawalExceedsBalance(amount, tokenBalance);

        amountRefundedToMessageIds[messageId][token] = amount;
        emit UpdatedAmountRefunded(messageId, token, amountBefore, amount);

        IERC20(token).safeTransfer(beneficiary, amount);
    }

    /**
     * @dev This function is called when receiving an inbound message.
     * @param any2EvmMessage contains CCIP message info such as data (message) and bridged token amounts
    */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        onlyAllowlisted(
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address))
        )
    {

        bytes4 functionSelector = FunctionSelectorDecoder.decodeFunctionSelector(any2EvmMessage.data);
        // For depositIntoStrategy: approve RestakingConnector to transfer tokens to EigenAgent
        if (functionSelector == IStrategyManager.depositIntoStrategy.selector) {
            for (uint32 i = 0; i < any2EvmMessage.destTokenAmounts.length; ++i) {
                IERC20(any2EvmMessage.destTokenAmounts[i].token).approve(
                    address(restakingConnector),
                    any2EvmMessage.destTokenAmounts[i].amount
                );
            }
        }

        try restakingConnector.dispatchMessageToEigenAgent(any2EvmMessage)
            returns (IRestakingConnector.TransferTokensInfo[] memory transferTokensArray)
        {
            for (uint32 i = 0; i < transferTokensArray.length; ++i) {

                IRestakingConnector.TransferTokensInfo memory t = transferTokensArray[i];

                if (t.transferRoot != bytes32(0)) {
                    // If transferRoot is returned bridge to L2, then SenderCCIP transfers tokens to AgentOwner.
                    this.sendMessagePayNative(
                        BaseSepolia.ChainSelector, // destination chain
                        senderContractL2,
                        t.transferToAgentOwnerMessage,
                        t.transferToken, // L1 token to burn/lock
                        t.transferAmount,
                        0 // use default gasLimit
                    );

                    if (t.transferType == IRestakingConnector.TransferType.Withdrawal) {
                        emit BridgingWithdrawalToL2(t.transferRoot, t.transferToken, t.transferAmount);

                    } else if (t.transferType == IRestakingConnector.TransferType.RewardsClaim) {
                        emit BridgingRewardsToL2(t.transferRoot, t.transferToken, t.transferAmount);

                    }
                }
                // EigenAgent executes message successfully.
                emit MessageReceived(
                    any2EvmMessage.messageId,
                    any2EvmMessage.sourceChainSelector,
                    abi.decode(any2EvmMessage.sender, (address)), // sender contract on L2
                    t.transferToken,
                    t.transferAmount
                );
            }

        } catch (bytes memory customError) {

            bytes4 errorSelector = FunctionSelectorDecoder.decodeErrorSelector(customError);
            // Decode and try catch the EigenAgentExecutionError

            if (errorSelector == IRestakingConnector.EigenAgentExecutionError.selector) {
                // If there were bridged tokens and the deposit has not been refunded yet...
                // (there should only be 1 token for deposits, but handle input destTokenAmounts[] as an array)
                for (uint32 i = 0; i < any2EvmMessage.destTokenAmounts.length; ++i) {

                    address tokenAddress = any2EvmMessage.destTokenAmounts[i].token;
                    uint256 tokenAmount = any2EvmMessage.destTokenAmounts[i].amount;

                    if (
                        tokenAmount > 0 &&
                        tokenAddress != address(0) &&
                        amountRefundedToMessageIds[any2EvmMessage.messageId][tokenAddress] <= 0
                    ) {
                        // ...mark messageId as refunded
                        amountRefundedToMessageIds[any2EvmMessage.messageId][tokenAddress] = tokenAmount;
                        // ...then initiate a refund back to the signer on L2
                        return _refundToSignerAfterExpiry(customError, tokenAddress, tokenAmount);

                    } else {
                        // Transaction not refundable (or already refunded). Display original error instead
                        (
                            , // address signer
                            , // uint256 expiry
                            string memory errStr
                        ) = FunctionSelectorDecoder.decodeEigenAgentExecutionError(customError);

                        revert(errStr);
                    }
                }

            } else {
                // For other errors revert and try parse error message
                revert(string(customError));
            }
        }
    }

    /**
     * @dev This function is called when sending an outbound message.
     * @param _receiver The address of the receiver.
     * @param _text The string data to be sent.
     * @param _token The token to be transferred.
     * @param _amount The amount of the token to be transferred.
     * @param _feeTokenAddress Address of the token used for fees. Set address(0) for native gas.
     * @param _overrideGasLimit set the gaslimit manually. If 0, uses default gasLimits.
     * @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information
     * for sending a CCIP message.
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

    /**
     * @dev Allows users to manually retry EigenAgent execution messages until expiry
     * if the message fails due to out-of-gas errors, or other temporary issues.
     * After message expiry, manual executions that still revert with an EigenAgentExecutionError
     * will trigger a refund to the original sender back on L2. This may happen for instance if
     * an Operator goes offline when attempting to deposit.
     * No other Eigenlayer call bridges tokens, this is the only edgecase to cover.
     */
    function _refundToSignerAfterExpiry(
        bytes memory customError,
        address tokenAddress,
        uint256 tokenAmount
    ) private {

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
                tokenAddress, // L1 token to burn/lock
                tokenAmount,
                0 // use default gasLimit
            );

            emit RefundingDeposit(signer, tokenAddress, tokenAmount);

        } else {
            // Otherwise if message hasn't expired, allow manual execution retries
            revert IRestakingConnector.ExecutionErrorRefundAfterExpiry(
                errStr,
                "Manually execute to refund after timestamp:",
                expiry
            );
        }
    }
}

