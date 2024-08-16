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


contract SenderCCIP is BaseMessengerCCIP, FunctionSelectorDecoder, EigenlayerMsgDecoders, EigenlayerMsgEncoders {

    event SendingWithdrawalToStaker(address indexed, uint256 indexed, bytes32 indexed);

    event UnknownFunctionSelector(bytes indexed);

    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);

    event WithdrawalCommitted(bytes32 indexed, address indexed, uint256 indexed);

    struct WithdrawalTransfer {
        address staker;
        uint256 amount;
        address tokenDestination;
    }

    mapping(bytes32 => WithdrawalTransfer) public withdrawalTransferCommittments;

    mapping(bytes32 => bool) public withdrawalRootsSpent;

    mapping(bytes4 => uint256) internal gasLimitsForFunctionSelectors;


    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    constructor(
        address _router,
        address _link
    ) BaseMessengerCCIP(_router, _link) {

        // depositIntoStrategy: [gas: 565_307]
        gasLimitsForFunctionSelectors[0xf7e784ef] = 600_000;

        // depositIntoStrategyWithSignature: [gas: 713_400]
        gasLimitsForFunctionSelectors[0x32e89ace] = 800_000;

        // queueWithdrawals: [gas: x]
        gasLimitsForFunctionSelectors[0x0dd8dd02] = 700_000;

        // queueWithdrawalsWithSignature: [gas: 603_301]
        gasLimitsForFunctionSelectors[0xa140f06e] = 800_000;

        // completeQueuedWithdrawals: [gas: 645_948]
        gasLimitsForFunctionSelectors[0x54b2bf29] = 800_000;
    }

    function mockCCIPReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) public {
        _ccipReceive(any2EvmMessage);
    }

    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage)
        internal
        override
        virtual
        onlyAllowlisted(
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address))
        )
    {
        s_lastReceivedMessageId = any2EvmMessage.messageId;
        s_lastReceivedText = abi.decode(any2EvmMessage.data, (string));
        if (any2EvmMessage.destTokenAmounts.length > 0) {
            s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
            s_lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;
        } else {
            s_lastReceivedTokenAddress = address(0);
            s_lastReceivedTokenAmount = 0;
        }

        bytes memory message = any2EvmMessage.data;
        string memory text_msg;
        bytes4 functionSelector = decodeFunctionSelector(message);

        if (functionSelector == 0x27167d10) {
            // keccak256(abi.encode("transferToStaker(bytes32)")) == 0x27167d10

            TransferToStakerMessage memory transferToStakerMsg = decodeTransferToStakerMessage(message);

            bytes32 withdrawalRoot = transferToStakerMsg.withdrawalRoot;

            WithdrawalTransfer memory withdrawalTransfer;
            withdrawalTransfer = withdrawalTransferCommittments[withdrawalRoot];

            address staker = withdrawalTransfer.staker;
            uint256 amount = withdrawalTransfer.amount;
            address tokenDestination = withdrawalTransfer.tokenDestination;

            // checks-effects-interactions
            // delete withdrawalRoot entry and mark the withdrawalRoot as spent
            // to prevent multiple withdrawals
            delete withdrawalTransferCommittments[withdrawalRoot];
            withdrawalRootsSpent[withdrawalRoot] = true;

            emit SendingWithdrawalToStaker(staker, amount, withdrawalRoot);

            IERC20(tokenDestination).transfer(staker, amount);
            text_msg = "completed eigenlayer withdrawal and transferred token to L2 staker";

        } else {

            emit UnknownFunctionSelector(message);
            text_msg = "messaging decoding failed";
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address)),
            text_msg,
            s_lastReceivedTokenAddress,
            s_lastReceivedTokenAmount
        );
    }


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

        Client.EVMTokenAmount[] memory tokenAmounts;
        if (_amount == 0) {
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

        bytes4 functionSelector = decodeFunctionSelector(message);

        if (functionSelector == 0x54b2bf29) {
            (
                IDelegationManager.Withdrawal memory withdrawal
                ,
                ,
                ,
            ) = decodeCompleteWithdrawalMessage(message);

            bytes32 withdrawalRoot = calculateWithdrawalRoot(withdrawal);

            // Check for spent withdrawalRoots to prevent withdrawalRoot reuse
            require(
                withdrawalRootsSpent[withdrawalRoot] == false,
                "withdrawalRoot has already been used"
            );
            // Commit to WithdrawalTransfer(staker, amount, token) before sending completeWithdrawal message,
            // so that when the message returns with withdrawalRoot, we use it to lookup (staker, amount)
            // to transfer the bridged withdrawn funds to.
            withdrawalTransferCommittments[withdrawalRoot] = WithdrawalTransfer({
                staker: withdrawal.staker,
                amount: withdrawal.shares[0],
                tokenDestination: ArbSepolia.BridgeToken
            });

            emit WithdrawalCommitted(withdrawalRoot, withdrawal.staker, withdrawal.shares[0]);
        } else {
            emit UnknownFunctionSelector(message);
        }

        uint256 gasLimit = gasLimitsForFunctionSelectors[functionSelector];

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

