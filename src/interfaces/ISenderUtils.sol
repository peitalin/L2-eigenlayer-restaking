// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

interface ISenderUtils {

    struct WithdrawalTransfer {
        address withdrawer;
        uint256 amount;
        address tokenDestination;
        address agentOwner;
    }

    function handleTransferToAgentOwner(bytes memory message) external returns (
        address agentOwner,
        uint256 amount,
        address tokenL2Address
    );

    function withdrawalTransferCommittments()
        external
        returns (ISenderUtils.WithdrawalTransfer memory);

    function calculateWithdrawalRoot(IDelegationManager.Withdrawal memory withdrawal)
        external pure
        returns (bytes32);

    function commitWithdrawalRootInfo(bytes memory message, address tokenDestination) external;

    function setFunctionSelectorName(bytes4 functionSelector, string memory _name) external;

    function getFunctionSelectorName(bytes4 functionSelector) external returns (string memory);

    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) external;

    function getGasLimitForFunctionSelector(bytes4 functionSelector) external returns (uint256);
}


