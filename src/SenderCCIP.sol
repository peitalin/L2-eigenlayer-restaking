// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BaseMessengerCCIP} from "./BaseMessengerCCIP.sol";
import {FunctionSelectorDecoder} from "./FunctionSelectorDecoder.sol";
import {EigenlayerMsgDecoders} from "./utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "./utils/EigenlayerMsgEncoders.sol";
import {TransferToStakerMessage} from "./interfaces/IRestakingConnector.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ArbSepolia} from "../script/Addresses.sol";

import {console} from "forge-std/Test.sol";


/// @title - Arb L2 Messenger Contract: sends Eigenlayer messages to L1,
/// and receives responses from L1 (e.g. queueing withdrawals).
contract SenderCCIP is BaseMessengerCCIP, FunctionSelectorDecoder, EigenlayerMsgDecoders, EigenlayerMsgEncoders {

    event SendingWithdrawalToStaker(address indexed, uint256 indexed, bytes32 indexed);

    event MalformedMessagePayload(bytes indexed);

    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);

    event WithdrawalRootCommitted(bytes32 indexed, address indexed, uint256 indexed);

    mapping(bytes32 => address) public withdrawalRootToStaker;

    mapping(bytes32 => uint256) public withdrawalRootToShares;

    mapping(bytes32 => address) public withdrawalRootToL2TokenAddr;

    mapping(bytes4 => uint256) internal gasLimitsForFunctionSelectors;


    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    constructor(
        address _router,
        address _link
    ) BaseMessengerCCIP(_router, _link) {

        // depositIntoStrategy: [gas: 565,307]
        gasLimitsForFunctionSelectors[0xf7e784ef] = 600_000;

        // depositIntoStrategyWithSignature: [gas: 713,400]
        gasLimitsForFunctionSelectors[0x32e89ace] = 800_000;

        // queueWithdrawals: [gas: ?]
        gasLimitsForFunctionSelectors[0x0dd8dd02] = 700_000;

        // queueWithdrawalsWithSignature: [gas: 603,301]
        gasLimitsForFunctionSelectors[0xa140f06e] = 800_000;

        // completeQueuedWithdrawals: [gas: 645,948]
        gasLimitsForFunctionSelectors[0x54b2bf29] = 800_000;
    }

    function mockCCIPReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) public {
        _ccipReceive(any2EvmMessage);
    }

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
        )
    {
        s_lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        s_lastReceivedText = abi.decode(any2EvmMessage.data, (string)); // abi-decoding of the sent text
        // Expect one token to be transferred at once, but you can transfer several tokens.
        s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
        s_lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;

        address token = any2EvmMessage.destTokenAmounts[0].token;

        bytes memory message = any2EvmMessage.data;

        bytes4 functionSelector = decodeFunctionSelector(message);
        string memory text_msg;

        if (functionSelector == 0x27167d10) {
            // keccak256(abi.encode("transferToStaker(bytes32)")) == 0x27167d10

            TransferToStakerMessage memory transferToStakerMsg = decodeTransferToStakerMessage(message);

            bytes32 withdrawalRoot = transferToStakerMsg.withdrawalRoot;

            address staker = withdrawalRootToStaker[withdrawalRoot];
            uint256 amount = withdrawalRootToShares[withdrawalRoot];
            address token_destination = withdrawalRootToL2TokenAddr[withdrawalRoot];

            emit SendingWithdrawalToStaker(staker, amount, withdrawalRoot);

            IERC20(token_destination).transfer(staker, amount);
            text_msg = "completed eigenlayer withdrawal and transferred token to L2 staker";
        } else {

            emit MalformedMessagePayload(message);
            text_msg = "messaging decoding failed";
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            text_msg,
            any2EvmMessage.destTokenAmounts[0].token,
            any2EvmMessage.destTokenAmounts[0].amount
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

        // depending on the functionSelector choose different CCIP message types
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });

        bytes memory message = abi.encode(_text);

        bytes4 functionSelector = decodeFunctionSelector(message);

        if (functionSelector == 0x54b2bf29) {
            // bytes4(keccak256("completeQueuedWithdrawal((address,address,address,uint256,address[],uint256[]),address[],uint256,bool)")) == 0x54b2bf29
            (
                IDelegationManager.Withdrawal memory withdrawal
                , // IERC20[] memory _tokensToWithdraw // token address on L1, not L2
                , // uint256 _middlewareTimesIndex
                , // bool _receiveAsTokens
            ) = decodeCompleteWithdrawalMessage(message);
            // before dispatching the message to L1, committ withdrawalRoot and associated data
            bytes32 withdrawalRoot = calculateWithdrawalRoot(withdrawal);
            // commit to (staker, amount, token) before dispatching completeWithdrawal message:
            // so that when the message returns with withdrawalRoot we use it to lookup who to transfer
            // the withdrawn amounts back to
            withdrawalRootToStaker[withdrawalRoot] = withdrawal.staker;
            withdrawalRootToShares[withdrawalRoot] = withdrawal.shares[0];
            withdrawalRootToL2TokenAddr[withdrawalRoot] = ArbSepolia.BridgeToken;

            emit WithdrawalRootCommitted(withdrawalRoot, withdrawal.staker, withdrawal.shares[0]);

        } else {

            emit MalformedMessagePayload(message);

        }

        uint256 gasLimit = gasLimitsForFunctionSelectors[functionSelector];

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

    /// @notice Returns the keccak256 hash of `withdrawal`.
    // Same as DelegateManager.sol in Eigenlayer on L1
    function calculateWithdrawalRoot(
        IDelegationManager.Withdrawal memory withdrawal
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(withdrawal));
    }

    function setGasLimitForFunctionSelector(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) public onlyOwner {

        require(functionSelectors.length == gasLimits.length, "input arrays must have the same length");

        for (uint256 i = 0; i < gasLimits.length; ++i) {
            gasLimitsForFunctionSelectors[functionSelectors[i]] = gasLimits[i];
            emit SetGasLimitForFunctionSelector(functionSelectors[i], gasLimits[i]);
        }
    }

    function getGasLimitForFunctionSelector(bytes4 functionSelector) public view returns (uint256) {
        return gasLimitsForFunctionSelectors[functionSelector];
    }
}

