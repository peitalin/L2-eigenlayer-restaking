// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";


interface ISenderHooks {

    struct FundsTransfer {
        uint256 amount;
        address agentOwner;
    }

    function getSenderCCIP() external view returns (address);

    function setSenderCCIP(address newSenderCCIP) external;

    function getGasLimitForFunctionSelector(bytes4 functionSelector) external returns (uint256);

    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) external;

    function getFundsTransferCommitment(bytes32 transferRoot)
        external
        returns (ISenderHooks.FundsTransfer memory);

    function isTransferRootSpent(bytes32 transferRoot) external returns (bool);

    // function calculateWithdrawalRoot(IDelegationManager.Withdrawal memory withdrawal)
    //     external
    //     pure
    //     returns (bytes32);

    function calculateWithdrawalTransferRoot(
        bytes32 withdrawalRoot,
        uint256 amount,
        address agentOwner
    ) external pure returns (bytes32);

    // function calculateRewardsRoot(IRewardsCoordinator.RewardsMerkleClaim memory claim)
    //     external
    //     pure
    //     returns (bytes32);

    function calculateRewardsTransferRoot(
        bytes32 rewardsRoot,
        uint256 rewardAmount,
        address rewardToken,
        address agentOwner
    ) external pure returns (bytes32);

    function beforeSendCCIPMessage(
        bytes memory message,
        address tokenL2,
        uint256 amount
    ) external returns (uint256 gasLimit);

    function handleTransferToAgentOwner(bytes memory message)
        external
        returns (address agentOwner, uint256 amount);

}


