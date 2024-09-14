// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

interface ISenderHooks {

    struct WithdrawalTransfer {
        uint256 amount;
        address agentOwner;
    }

    struct RewardsTransfer {
        uint256 amount;
        address recipient;
    }

    function getSenderCCIP() external view returns (address);

    function setSenderCCIP(address newSenderCCIP) external;

    function getGasLimitForFunctionSelector(bytes4 functionSelector) external returns (uint256);

    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) external;

    function getWithdrawalTransferCommitment(bytes32 withdrawalTransferRoot)
        external
        returns (ISenderHooks.WithdrawalTransfer memory);

    function isWithdrawalTransferRootSpent(bytes32 withdrawalTransferRoot) external returns (bool);

    function calculateWithdrawalRoot(IDelegationManager.Withdrawal memory withdrawal)
        external
        pure
        returns (bytes32);

    function calculateWithdrawalTransferRoot(
        bytes32 withdrawalRoot,
        uint256 amount,
        address agentOwner
    ) external pure returns (bytes32);

    function calculateRewardsTransferRoot(
        bytes32 rewardsRoot,
        uint256 rewardAmount,
        address rewardToken,
        address agentOwner
    ) external pure returns (bytes32);

    function beforeSendCCIPMessage(bytes memory message, address tokenL2) external;

    function handleTransferToAgentOwner(bytes memory message)
        external
        returns (address agentOwner, uint256 amount);

}


