// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct EigenlayerDeposit6551Msg {
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

event EigenlayerQueueWithdrawalsParams(
    uint256 indexed amount,
    address indexed staker
);

struct TransferToAgentOwnerMsg {
    bytes32 withdrawalRoot;
    address agentOwner;
    bytes32 agentOwnerRoot;
}
event TransferToAgentOwnerParams(
    bytes32 indexed withdrawalRoot,
    address indexed agentOwner,
    bytes32 indexed agentOwnerRoot
);

interface IEigenlayerMsgDecoders {

    function decodeDepositWithSignature6551Msg(
        bytes memory message
    ) external returns (EigenlayerDeposit6551Msg memory);


    function decodeQueueWithdrawalsMsg(
        bytes memory message
    ) external returns (
        IDelegationManager.QueuedWithdrawalParams[] memory,
        uint256, // expiry
        bytes memory  // signature
    );


    function decodeCompleteWithdrawalMsg(
        bytes memory message
    ) external returns (
        IDelegationManager.Withdrawal memory,
        IERC20[] memory,
        uint256,
        bool,
        uint256,
        bytes memory
    );

    function decodeTransferToAgentOwnerMsg(bytes memory message) external returns (
        TransferToAgentOwnerMsg memory
    );

    function decodeDelegateToBySignatureMsg(
        bytes memory message
    ) external returns (
        address,
        address,
        ISignatureUtils.SignatureWithExpiry memory,
        ISignatureUtils.SignatureWithExpiry memory,
        bytes32
    );

    function decodeUndelegateMsg(bytes memory message) external returns (address);
}