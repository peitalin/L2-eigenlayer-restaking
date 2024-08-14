// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {
    EigenlayerDepositMessage,
    EigenlayerDepositWithSignatureMessage,
    IRestakingConnector
} from "./interfaces/IRestakingConnector.sol";
import {ISenderCCIP} from "./interfaces/ISenderCCIP.sol";
import {IReceiverCCIP} from "./interfaces/IReceiverCCIP.sol";
import {BaseMessengerCCIP} from "./BaseMessengerCCIP.sol";
import {FunctionSelectorDecoder} from "./FunctionSelectorDecoder.sol";

import {Adminable} from "./utils/Adminable.sol";
import {ArbSepolia} from "../script/Addresses.sol";
import {EigenlayerMsgEncoders} from "./utils/EigenlayerMsgEncoders.sol";
import {TransferToStakerMessage} from "./interfaces/IRestakingConnector.sol";


/// ETH L1 Messenger Contract: receives Eigenlayer messages from L2 and processes them.
contract ReceiverCCIP is BaseMessengerCCIP, FunctionSelectorDecoder, EigenlayerMsgEncoders {

    IRestakingConnector public restakingConnector;
    address public senderContractL2Addr;

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    /// @param _restakingConnector address of eigenlayer restaking middleware contract.
    constructor(
        address _router,
        address _link,
        address _restakingConnector
        // address _senderContractL2Addr
    ) BaseMessengerCCIP(_router, _link) {
        restakingConnector = IRestakingConnector(_restakingConnector);
        // senderContractL2Addr = ISenderCCIP(_senderContractL2Addr);
    }

    function getSenderContractL2Addr() public view returns (address) {
        // address, contract only exists on L2
        return senderContractL2Addr;
    }

    function setSenderContractL2Addr(address _senderContractL2Addr) public onlyOwner {
        senderContractL2Addr = _senderContractL2Addr;
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
        ) // Make sure source chain and sender are allowlisted
    {
        s_lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        s_lastReceivedText = abi.decode(any2EvmMessage.data, (string)); // abi-decoding of the sent text
        // Expect one token to be transferred at once, but you can transfer several tokens.
        s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
        s_lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;

        if (address(restakingConnector) == address(0)) revert("restakingConnector not set");

        bytes memory message = any2EvmMessage.data;
        bytes4 functionSelector = decodeFunctionSelector(message);

        (
            IDelegationManager delegationManager,
            IStrategyManager strategyManager,
            IStrategy strategy
        ) = restakingConnector.getEigenlayerContracts();

        IERC20 underlyingToken = strategy.underlyingToken();
        string memory textMsg = "no matching functionSelector";
        uint256 amountMsg = any2EvmMessage.destTokenAmounts[0].amount;


        if (functionSelector == 0xf7e784ef) {
            // bytes4(keccak256("depositIntoStrategy(uint256,address)")) == 0xf7e784ef
            EigenlayerDepositMessage memory eigenMsg;
            eigenMsg = restakingConnector.decodeDepositMessage(message);
            // Receiver contract approves eigenlayer StrategyManager for deposits
            underlyingToken.approve(address(strategyManager), eigenMsg.amount);
            // deposit into Eigenlayer
            strategyManager.depositIntoStrategy(strategy, underlyingToken, eigenMsg.amount);
            textMsg = "depositIntoStrategy()";
            amountMsg = eigenMsg.amount;
        }

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
            // amountMsg = eigenMsg.amount;
        }

        if (functionSelector == 0xa140f06e) {
            // bytes4(keccak256("queueWithdrawalsWithSignature((address[],uint256[],address,address,bytes)[])")),

            IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalsWithSigParams =
                restakingConnector.decodeQueueWithdrawalsWithSignatureMessage(message);

            delegationManager.queueWithdrawalsWithSignature(
                queuedWithdrawalsWithSigParams
            );

            textMsg = "queueWithdrawalsWithSignature()";
            amountMsg = queuedWithdrawalsWithSigParams[0].shares[0];
        }

        if (functionSelector == 0x54b2bf29) {
            // bytes4(keccak256("completeQueuedWithdrawal((address,address,address,uint256,address[],uint256[]),address[],uint256,bool)")),
            (
                IDelegationManager.Withdrawal memory withdrawal,
                IERC20[] memory tokensToWithdraw,
                uint256 middlewareTimesIndex,
                bool receiveAsTokens
                // TODO: add signature for bridging back to L2 staker address
            ) = restakingConnector.decodeCompleteWithdrawalMessage(message);

            // TODO: check signature before completing withdrawal, to reduce griefing withdrawals

            // signatureUtils.checkSignature_EIP1271(_staker, digestHash, signature);

            delegationManager.completeQueuedWithdrawal(
                withdrawal,
                tokensToWithdraw,
                middlewareTimesIndex,
                receiveAsTokens
            );

            address original_staker = withdrawal.staker;
            uint256 amount = withdrawal.shares[0];
            // L2 Sender contract address
            address _senderContractL2Addr = getSenderContractL2Addr();

            // Approve L1 receiverContract to send ccip-BnM tokens to Router
            IERC20 token = withdrawal.strategies[0].underlyingToken();
            token.approve(address(this), amount);

            address token_destination = ArbSepolia.CcipBnM;

            // TODO: add signature for bridging back to L2 staker address
            // signature needs to sign over digestHash made up of:
            // amount, original_staker, token_destination, expiry, nonce.
            //
            // otherwise anyone can mock a CCIP message and drain funds on L2 sender contract
            string memory text_message = string(abi.encode(
                encodeTransferToStakerMsg(amount, original_staker, token_destination)
            ));

            /// return token to staker via bridge with message to transferToStaker
            this.sendMessagePayNative(
                ArbSepolia.ChainSelector, // destination chain
                _senderContractL2Addr,
                text_message,
                address(token), // L1 token address to burn/lock
                amount
            );

            textMsg = "completeQueuedWithdrawal()";
            // amountMsg = eigenMsg.amount;
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            textMsg,
            any2EvmMessage.destTokenAmounts[0].token,
            amountMsg
        );
    }

    bytes4 constant internal MAGICVALUE = 0x1626ba7e;

    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) public pure returns (bytes4 magicValue) {

        // implement some hash/signature scheme

        // if (Address.isContract(signer)) {
        //     require(
        //         IERC1271(signer).isValidSignature(digestHash, signature) == EIP1271_MAGICVALUE,
        //         "EIP1271SignatureUtils.checkSignature_EIP1271: ERC1271 signature verification failed"
        //     );
        // }
        // address signer = ECDSA.recover(digestHash, signature);

        // // bytes32 messageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _hash));
        // // if (signer == address(0)) {
        // //     return 0x00000000;
        // // } else if (signer == msg.sender) {
        // //     return 0x20c13b0b;
        // // } else {
        // //     return 0x00000000;
        // // }

        // IERC1271(signer).isValidSignature(digestHash, signature) == EIP1271_MAGICVALUE,
        return MAGICVALUE;
    }

}

