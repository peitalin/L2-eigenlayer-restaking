// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {BaseMessengerCCIP} from "./BaseMessengerCCIP.sol";
import {FunctionSelectorDecoder} from "./FunctionSelectorDecoder.sol";


/// @title - Arb L2 Messenger Contract: sends Eigenlayer messages to L1,
/// and receives responses from L1 (e.g. queueing withdrawals).
contract SenderCCIP is BaseMessengerCCIP, FunctionSelectorDecoder {

    mapping(bytes4 => uint256) gasLimitsForFunctionSelectors;

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    constructor(
        address _router,
        address _link
    ) BaseMessengerCCIP(_router, _link) {}

    /// handle a received message
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        virtual
        onlyAllowlisted(
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address))
        ) // Make sure source chain and sender are allowlisted
    {
        s_lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        s_lastReceivedText = abi.decode(any2EvmMessage.data, (string)); // abi-decoding of the sent text
        // Expect one token to be transferred at once, but you can transfer several tokens.
        s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
        s_lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            // msgForEigenlayer.staker,
            abi.decode(any2EvmMessage.data, (string)),
            any2EvmMessage.destTokenAmounts[0].token,
            any2EvmMessage.destTokenAmounts[0].amount
            // msgForEigenlayer.amount
        );
    }

    /// @notice Construct a CCIP message.
    /// @dev This function will create an EVM2AnyMessage struct with all the necessary information for programmable tokens transfer.
    /// @param _receiver The address of the receiver.
    /// @param _text The string data to be sent.
    /// @param _token The token to be transferred.
    /// @param _amount The amount of the token to be transferred.
    /// @param _feeTokenAddress The address of the token used for fees. Set address(0) for native gas.
    /// @return Client.EVM2AnyMessage Returns an EVM2AnyMessage struct which contains information for sending a CCIP message.
    function _buildCCIPMessage(
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) internal override returns (Client.EVM2AnyMessage memory) {
        // Set the token amounts
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });

        bytes memory message = abi.encode(_text); // ABI-encoded string
        bytes4 functionSelector = decodeFunctionSelector(message);
        uint256 gasLimit = 500_000;
        // increase gas limit for deposits into Eigenlayer

        if (functionSelector == 0xf7e784ef) {
            // depositIntoStrategy: [gas: 565,307]
            gasLimit = 600_000;
        }
        if (functionSelector == 0x32e89ace) {
            // depositIntoStrategyWithSignature: [gas: 713,400]
            gasLimit = 800_000;
        }
        if (functionSelector == 0x0dd8dd02) {
            // queueWithdrawals: [gas: ?]
            gasLimit = 800_000;
        }
        if (functionSelector == 0xa140f06e) {
            // queueWithdrawalsWithSignature: [gas: ?]
            gasLimit = 990_000;
        }
        if (functionSelector == 0x54b2bf29) {
            // completeQueuedWithdrawals: [gas: ?]
            gasLimit = 990_000;
        }

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver), // ABI-encoded receiver address
                data: message, // ABI-encoded string
                tokenAmounts: tokenAmounts, // The amount and type of token being transferred
                extraArgs: Client._argsToBytes(
                    // Additional arguments, setting gas limit
                    Client.EVMExtraArgsV1({ gasLimit: gasLimit })
                ),
                // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
                feeToken: _feeTokenAddress
            });
    }

    function setGasLimitsForFunctionSelectors(
        bytes4 functionSelector,
        uint256 gasLimit
    ) public onlyOwner {
        gasLimitsForFunctionSelectors[functionSelector] = gasLimit;
    }
}

