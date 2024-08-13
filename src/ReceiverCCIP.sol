// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {EigenlayerDepositMessage, EigenlayerDepositWithSignatureMessage} from "./interfaces/IRestakingConnector.sol";
import {BaseMessengerCCIP} from "./BaseMessengerCCIP.sol";
import {FunctionSelectorDecoder} from "./FunctionSelectorDecoder.sol";

import {console} from "forge-std/Test.sol";


/// ETH L1 Messenger Contract: receives Eigenlayer messages from L2 and processes them.
contract ReceiverCCIP is BaseMessengerCCIP, FunctionSelectorDecoder {

    IRestakingConnector public restakingConnector;

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    /// @param _restakingConnector address of eigenlayer restaking middleware contract.
    constructor(
        address _router,
        address _link,
        address _restakingConnector
    ) BaseMessengerCCIP(_router, _link) {
        restakingConnector = IRestakingConnector(_restakingConnector);
    }

    function getRestakingConnector() public view returns (IRestakingConnector) {
        return restakingConnector;
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
        string memory textMsg;
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

            console.log("msg.sender", msg.sender);
            console.log("withdrawer:", queuedWithdrawalParams[0].withdrawer);

            bytes32[] memory withdrawalRoots = delegationManager.queueWithdrawals(queuedWithdrawalParams);

            textMsg = "queueWithdrawals()";
            // amountMsg = eigenMsg.amount;
        }

        if (functionSelector == 0xa140f06e) {
            // bytes4(keccak256("queueWithdrawalsWithSignature((address[],uint256[],address,address,bytes)[])")),

            IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalsWithSigParams =
                restakingConnector.decodeQueueWithdrawalsWithSignatureMessage(message);

            console.log("staker", queuedWithdrawalsWithSigParams[0].staker);
            console.log("withdrawer:", queuedWithdrawalsWithSigParams[0].withdrawer);

            bytes32[] memory withdrawalRoots = delegationManager.queueWithdrawalsWithSignature(
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
            ) = restakingConnector.decodeCompleteWithdrawalMessage(message);

            delegationManager.completeQueuedWithdrawal(
                withdrawal,
                tokensToWithdraw,
                middlewareTimesIndex,
                receiveAsTokens
            );

            /// return token to staker via bridge

            textMsg = "completeQueuedWithdrawal()";
            // amountMsg = eigenMsg.amount;
        } else {
            textMsg = "no matching functionSelector";
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
    ) public view returns (bytes4 magicValue) {

        // implement some hash/signature scheme

        // if (Address.isContract(signer)) {
        //     require(
        //         IERC1271(signer).isValidSignature(digestHash, signature) == EIP1271_MAGICVALUE,
        //         "EIP1271SignatureUtils.checkSignature_EIP1271: ERC1271 signature verification failed"
        //     );
        // }
        // address signer = ECDSA.recover(digestHash, signature);
        // console.log("signer", signer);

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

