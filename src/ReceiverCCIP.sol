// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {
    EigenlayerDepositMessage,
    EigenlayerDepositWithSignatureMessage,
    TransferToStakerMessage
} from "./interfaces/IEigenlayerMsgDecoders.sol";
import {ISenderCCIP} from "./interfaces/ISenderCCIP.sol";
import {IReceiverCCIP} from "./interfaces/IReceiverCCIP.sol";
import {BaseMessengerCCIP} from "./BaseMessengerCCIP.sol";

import {BaseSepolia} from "../script/Addresses.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";



/// ETH L1 Messenger Contract: receives Eigenlayer messages from L2 and processes them.
contract ReceiverCCIP is BaseMessengerCCIP {

    IRestakingConnector public restakingConnector;
    address public senderContractL2Addr;

    error InvalidContractAddress(string msg);

    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    constructor(address _router, address _link) BaseMessengerCCIP(_router, _link) {}

    function initialize(
        IRestakingConnector _restakingConnector,
        ISenderCCIP _senderContractL2
    ) initializer public {

        if (address(_restakingConnector) == address(0))
            revert InvalidContractAddress("restakingConnector cannot be address(0)");

        if (address(_senderContractL2) == address(0))
            revert InvalidContractAddress("SenderCCIP cannot be address(0)");

        restakingConnector = _restakingConnector;
        senderContractL2Addr = address(_senderContractL2);

        BaseMessengerCCIP.__BaseMessengerCCIP_init();
    }

    function getSenderContractL2Addr() public view returns (address) {
        // address, contract only exists on L2
        return senderContractL2Addr;
    }

    function setSenderContractL2Addr(address _senderContractL2) public onlyOwner {
        senderContractL2Addr = _senderContractL2;
    }

    function getRestakingConnector() public view returns (IRestakingConnector) {
        return restakingConnector;
    }

    function setRestakingConnector(IRestakingConnector _restakingConnector) public onlyOwner {
        restakingConnector = _restakingConnector;
    }

    function mockCCIPReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) public {
        _ccipReceive(any2EvmMessage);
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
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

        bytes memory message = any2EvmMessage.data;
        bytes4 functionSelector = restakingConnector.decodeFunctionSelector(message);

        (
            IDelegationManager delegationManager,
            IStrategyManager strategyManager,
            IStrategy strategy
        ) = restakingConnector.getEigenlayerContracts();

        IERC20 underlyingToken = strategy.underlyingToken();
        string memory textMsg = "no matching functionSelector";
        uint256 amountMsg = s_lastReceivedTokenAmount;

        if (functionSelector == 0x32e89ace) {
            // bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")) == 0x32e89ace
            EigenlayerDepositWithSignatureMessage memory eigenMsg;
            eigenMsg = restakingConnector.decodeDepositWithSignatureMessage(message);
            // Receiver contract approves eigenlayer StrategyManager for deposits
            underlyingToken.approve(address(strategyManager), eigenMsg.amount);
            // deposit into Eigenlayer with user signature
            strategyManager.depositIntoStrategyWithSignature(
                IStrategy(eigenMsg.strategy),
                IERC20(eigenMsg.token),
                eigenMsg.amount,
                eigenMsg.staker,
                eigenMsg.expiry,
                eigenMsg.signature
            );
            textMsg = "depositIntoStrategyWithSignature()";
            amountMsg = eigenMsg.amount;
        }

        if (functionSelector == 0x0dd8dd02) {
            // bytes4(keccak256("queueWithdrawals((address[],uint256[],address)[])")),

            IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams =
                restakingConnector.decodeQueueWithdrawalsMessage(message);

            delegationManager.queueWithdrawals(queuedWithdrawalParams);

            textMsg = "queueWithdrawals()";
        }

        if (functionSelector == 0xa140f06e) {
            // bytes4(keccak256("queueWithdrawalsWithSignature((address[],uint256[],address,address,bytes)[])")),

            IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalsWithSigParams =
                restakingConnector.decodeQueueWithdrawalsWithSignatureMessage(message);

            require(queuedWithdrawalsWithSigParams.length > 0, "queuedWithdrawalsWithSigParams: length cannot be 0");

            address staker = queuedWithdrawalsWithSigParams[0].staker;
            // queueWithdrawal uses current nonce in the withdrawalRoot, the increments after
            // so save this nonce before dispatching queueWithdrawalsWithSignature
            uint256 nonce = delegationManager.cumulativeWithdrawalsQueued(staker);
            restakingConnector.setQueueWithdrawalBlock(staker, nonce);

            // Call QueueWithdrawalsWithSignature on Eigenlayer
            bytes32[] memory withdrawalRoots = delegationManager.queueWithdrawalsWithSignature(
                queuedWithdrawalsWithSigParams
            );

            textMsg = "queueWithdrawalsWithSignature()";
            amountMsg = queuedWithdrawalsWithSigParams[0].shares[0];
        }

        if (functionSelector == 0x54b2bf29) {
            // bytes4(keccak256("completeQueuedWithdrawal((address,address,address,uint256,address[],uint256[]),address[],uint256,bool)")) == 0x54b2bf29
            (
                IDelegationManager.Withdrawal memory withdrawal,
                IERC20[] memory tokensToWithdraw,
                uint256 middlewareTimesIndex,
                bool receiveAsTokens
            ) = restakingConnector.decodeCompleteWithdrawalMessage(message);

            // requires(msg.sender == withdrawal.withdrawer), so only this contract can withdraw
            // since all queuedWithdrawals are also done through this contract.
            // then it calculates withdrawalRoot ensuring staker/withdrawal/block is a valid withdrawal.
            delegationManager.completeQueuedWithdrawal(
                withdrawal,
                tokensToWithdraw,
                middlewareTimesIndex,
                receiveAsTokens
            );

            bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);

            // address original_staker = withdrawal.staker;
            uint256 amount = withdrawal.shares[0];
            // Approve L1 receiverContract to send ccip-BnM tokens to Router
            IERC20 token = withdrawal.strategies[0].underlyingToken();
            token.approve(address(this), amount);

            string memory text_message = string(restakingConnector.encodeTransferToStakerMsg(withdrawalRoot));

            /// return token to staker via bridge with message to transferToStaker
            this.sendMessagePayNative(
                BaseSepolia.ChainSelector, // destination chain
                senderContractL2Addr,
                text_message,
                address(token), // L1 token address to burn/lock
                amount
            );

            // textMsg = "completeQueuedWithdrawal()";
            textMsg = text_message;
        }

        if (functionSelector == 0x7f548071) {
            // bytes4(keccak256("delegateToBySignature(address,address,(bytes,uint256),(bytes,uint256),bytes32)")) == 0x7f548071
            (
                address staker,
                address operator,
                ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry,
                ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
                bytes32 approverSalt
            ) = restakingConnector.decodeDelegateToBySignature(message);

            delegationManager.delegateToBySignature(
                staker,
                operator,
                stakerSignatureAndExpiry,
                approverSignatureAndExpiry,
                approverSalt
            );
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            textMsg,
            s_lastReceivedTokenAddress,
            amountMsg
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

        bytes4 functionSelector = restakingConnector.decodeFunctionSelector(message);
        uint256 gasLimit = 600_000;

        if (functionSelector == 0x27167d10) {
            // bytes4(keccak256("transferToStaker(bytes32)")) == 0x27167d10
            gasLimit = 800_000;
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

