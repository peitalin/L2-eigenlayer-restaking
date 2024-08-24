// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {BaseMessengerCCIP} from "./BaseMessengerCCIP.sol";
import {TransferToStakerMessage} from "./interfaces/IEigenlayerMsgDecoders.sol";
import {ISenderUtils} from "./interfaces/ISenderUtils.sol";
import {BaseSepolia} from "../script/Addresses.sol";


contract SenderCCIP is BaseMessengerCCIP {

    event SendingWithdrawalToStaker(address indexed, uint256 indexed, address indexed);

    event MatchedReceivedFunctionSelector(bytes4 indexed, string indexed);

    event MatchedSentFunctionSelector(bytes4 indexed, string indexed);

    event WithdrawalCommitted(bytes32 indexed, address indexed, uint256 indexed);

    struct WithdrawalTransfer {
        address staker;
        uint256 amount;
        address tokenDestination;
    }

    mapping(bytes32 => WithdrawalTransfer) public withdrawalTransferCommittments;

    mapping(bytes32 => bool) public withdrawalRootsSpent;

    ISenderUtils public senderUtils;

    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    constructor(address _router, address _link) BaseMessengerCCIP(_router, _link) {}

    function initialize(ISenderUtils _senderUtils) initializer public {

        require(address(_senderUtils) != address(0), "_senderUtils cannot be address(0)");
        senderUtils = _senderUtils;

        BaseMessengerCCIP.__BaseMessengerCCIP_init();
    }

    function setSenderUtils(ISenderUtils _senderUtils) external onlyOwner {
        senderUtils = _senderUtils;
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

        if (any2EvmMessage.destTokenAmounts.length > 0) {
            s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
            s_lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;
        } else {
            s_lastReceivedTokenAddress = address(0);
            s_lastReceivedTokenAmount = 0;
        }

        bytes memory message = any2EvmMessage.data;
        string memory text_msg;
        bytes4 functionSelector = senderUtils.decodeFunctionSelector(message);

        if (functionSelector == 0x27167d10) {
            // keccak256(abi.encode("transferToStaker(bytes32)")) == 0x27167d10
            TransferToStakerMessage memory transferToStakerMsg = senderUtils.decodeTransferToStakerMessage(message);

            bytes32 withdrawalRoot = transferToStakerMsg.withdrawalRoot;

            WithdrawalTransfer memory withdrawalTransfer = withdrawalTransferCommittments[withdrawalRoot];

            address staker = withdrawalTransfer.staker;
            uint256 amount = withdrawalTransfer.amount;
            address tokenDestination = withdrawalTransfer.tokenDestination;
            emit SendingWithdrawalToStaker(staker, amount, tokenDestination);
            // address tokenDestination = BaseSepolia.CcipBnM;
            // emit SendingWithdrawalToStaker(staker, amount, tokenDestination);

            // checks-effects-interactions
            // delete withdrawalRoot entry and mark the withdrawalRoot as spent
            // to prevent multiple withdrawals
            // delete withdrawalTransferCommittments[withdrawalRoot];
            withdrawalRootsSpent[withdrawalRoot] = true;

            IERC20(tokenDestination).approve(address(this), amount);
            IERC20(tokenDestination).transfer(staker, amount);

            text_msg = "completed eigenlayer withdrawal and transferred token to L2 staker";

        } else {

            emit MatchedReceivedFunctionSelector(functionSelector, "UnknownFunctionSelector");
            text_msg = "unknown message";
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address)),
            text_msg,
            s_lastReceivedTokenAddress = address(0),
            s_lastReceivedTokenAmount = 0
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

        bytes4 functionSelector = senderUtils.decodeFunctionSelector(message);

        // When User sends a message to CompleteQueuedWithdrawal from L2 to L1
        if (functionSelector == 0x54b2bf29) {
            // 0x54b2bf29 = abi.encode(keccask256(completeQueuedWithdrawal((address,address,address,uint256,address[],uint256[]),address[],uint256,bool)))
            (
                IDelegationManager.Withdrawal memory withdrawal
                , // tokensToWithdraw,
                , // middlewareTimesIndex
                , // receiveAsTokens
                , // expiry
                , // signature
            ) = senderUtils.decodeCompleteWithdrawalMessage(message);

            bytes32 withdrawalRoot = calculateWithdrawalRoot(withdrawal);

            // Check for spent withdrawalRoots to prevent wasted CCIP message
            // as it will fail to withdraw from Eigenlayer
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
                tokenDestination: _token
            });

            emit WithdrawalCommitted(withdrawalRoot, withdrawal.staker, withdrawal.shares[0]);
        } else {
            string memory _functionSelectorName = senderUtils.getFunctionSelectorName(functionSelector);
            emit MatchedSentFunctionSelector(functionSelector, _functionSelectorName);
        }

        uint256 gasLimit = senderUtils.getGasLimitForFunctionSelector(functionSelector);

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

    function getWithdrawal(bytes32 withdrawalRoot) public view returns (WithdrawalTransfer memory) {
        return withdrawalTransferCommittments[withdrawalRoot];
    }

    function calculateWithdrawalRoot(
        IDelegationManager.Withdrawal memory withdrawal
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(withdrawal));
    }

}

