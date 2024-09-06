// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

interface ISenderHooks {

    struct WithdrawalTransfer {
        uint256 amount;
        address agentOwner;
    }

    function getSenderCCIP() external view returns (address);

    function setSenderCCIP(address newSenderCCIP) external;

    function isWithdrawalTransferRootSpent(bytes32 withdrawalTransferRoot) external returns (bool);

    function handleTransferToAgentOwner(bytes memory message)
        external
        returns (address agentOwner, uint256 amount);

    function beforeSendCCIPMessage(bytes memory message, address tokenL2) external;

    function getWithdrawalTransferCommitment(bytes32 withdrawalTransferRoot)
        external
        returns (ISenderHooks.WithdrawalTransfer memory);

    function calculateWithdrawalRoot(IDelegationManager.Withdrawal memory withdrawal)
        external pure
        returns (bytes32);

    function calculateWithdrawalTransferRoot(
        bytes32 withdrawalRoot,
        uint256 amount,
        address tokenL2,
        address agentOwner
    ) external pure returns (bytes32);

    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) external;

    function getGasLimitForFunctionSelector(bytes4 functionSelector)
        external
        returns (uint256);
}


