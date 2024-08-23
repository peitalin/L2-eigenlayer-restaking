// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct EigenlayerDeposit6551Message {
    address strategy;
    address token;
    uint256 amount;
    address staker;
    uint256 expiry;
    bytes signature;
}
event EigenlayerDeposit6551Params(
    address indexed staker,
    address indexed strategy,
    address token,
    uint256 indexed amount
);

struct EigenlayerDepositWithSignatureMessage {
    uint256 expiry;
    address strategy;
    address token;
    uint256 amount;
    address staker;
    bytes signature;
}
event EigenlayerDepositWithSignatureParams(
    uint256 indexed amount,
    address indexed staker
);

event EigenlayerQueueWithdrawalsParams(
    uint256 indexed amount,
    address indexed staker
);

event EigenlayerQueueWithdrawalsWithSignatureParams(
    uint256 indexed amount,
    address indexed staker,
    bytes indexed signature
);

struct TransferToStakerMessage {
    bytes32 withdrawalRoot;
}
event TransferToStakerParams(
    bytes32 indexed withdrawalRoot
);

struct QueuedWithdrawalWithSignatureParams {
    // Array of strategies that the QueuedWithdrawal contains
    IStrategy[] strategies;
    // Array containing the amount of shares in each Strategy in the `strategies` array
    uint256[] shares;
    // The address of the withdrawer
    address withdrawer;
    // The address of the staker
    address staker;
    // signature of the staker
    bytes signature;
    // expiration timestamp of the signature
    uint256 expiry;
}


interface IEigenlayerMsgDecoders {

    function decodeDepositWithSignature6551Msg(
        bytes memory message
    ) external returns (EigenlayerDeposit6551Message memory);


    function decodeDepositWithSignatureMsg(
        bytes memory message
    ) external returns (EigenlayerDepositWithSignatureMessage memory);


    function decodeQueueWithdrawalsMessage(
        bytes memory message
    ) external returns (
        IDelegationManager.QueuedWithdrawalParams[] memory,
        uint256, // expiry
        bytes memory  // signature
    );


    function decodeQueueWithdrawalsWithSignatureMessage(
        bytes memory message
    ) external returns (
        QueuedWithdrawalWithSignatureParams[] memory
    );


    function decodeCompleteWithdrawalMessage(
        bytes memory message
    ) external returns (
        IDelegationManager.Withdrawal memory,
        IERC20[] memory,
        uint256,
        bool
    );

    function decodeTransferToStakerMessage(bytes memory message) external returns (
        TransferToStakerMessage memory
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