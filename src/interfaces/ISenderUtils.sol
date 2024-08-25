// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IEigenlayerMsgDecoders} from "./IEigenlayerMsgDecoders.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

interface ISenderUtils is IEigenlayerMsgDecoders {

    struct WithdrawalTransfer {
        address withdrawer;
        uint256 amount;
        address tokenDestination;
    }

    function decodeFunctionSelector(bytes memory message) external returns (bytes4);

    function setFunctionSelectorName(bytes4 functionSelector, string memory _name) external;

    function getFunctionSelectorName(bytes4 functionSelector) external returns (string memory);

    function handleTransferToAgentOwner(bytes memory message) external returns (
        address agentOwner,
        uint256 amount,
        address tokenL2Address
    );

    function commitWithdrawalRootInfo(bytes memory message, address tokenDestination) external;

    function setGasLimitsForFunctionSelectors(bytes4 functionSelector, uint256 gasLimit) external;

    function getGasLimitForFunctionSelector(bytes4 functionSelector) external returns (uint256);

    function getWithdrawal(bytes32 withdrawalRoot) external view returns (WithdrawalTransfer memory);

    function calculateWithdrawalRoot(
        IDelegationManager.Withdrawal memory withdrawal
    ) external pure returns (bytes32);
}


