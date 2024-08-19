// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// Deposit
import {
    EigenlayerDepositMessage,
    EigenlayerDepositParams
} from "../interfaces/IRestakingConnector.sol";
// DepositWithSignature
import {
    EigenlayerDepositWithSignatureMessage,
    EigenlayerDepositWithSignatureParams
} from "../interfaces/IRestakingConnector.sol";
// QueueWithdrawals
import {EigenlayerQueueWithdrawalsParams} from "../interfaces/IRestakingConnector.sol";


interface IEigenlayerMsgDecoders {

    function decodeDepositWithSignatureMessage(
        bytes memory message
    ) external returns (EigenlayerDepositWithSignatureMessage memory);


    function decodeQueueWithdrawalsMessage(
        bytes memory message
    ) external returns (IDelegationManager.QueuedWithdrawalParams[] memory);


    function decodeQueueWithdrawalsWithSignatureMessage(
        bytes memory message
    ) external returns (
        IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory
    );


    function decodeCompleteWithdrawalMessage(
        bytes memory message
    ) external returns (
        IDelegationManager.Withdrawal memory,
        IERC20[] memory,
        uint256,
        bool
    );

    function decodeDelegateToBySignature(
        bytes memory message
    ) external returns (
        address,
        address,
        ISignatureUtils.SignatureWithExpiry memory,
        ISignatureUtils.SignatureWithExpiry memory,
        bytes32
    );

    function decodeUndelegate(bytes memory message) external returns (address);
}