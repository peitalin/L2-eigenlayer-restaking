// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IEigenlayerMsgDecoders} from "../interfaces/IEigenlayerMsgDecoders.sol";


interface IRestakingConnector is IEigenlayerMsgDecoders {

    function decodeFunctionSelector(bytes memory message) external returns (bytes4);

    function encodeHandleTransferToAgentOwnerMsg(
        bytes32 withdrawalRoot,
        address agentOwner
    ) external returns (bytes memory);

    function getEigenlayerContracts() external returns (
        IDelegationManager,
        IStrategyManager,
        IStrategy
    );

    function setEigenlayerContracts(
        IDelegationManager _delegationManager,
        IStrategyManager _strategyManager,
        IStrategy _strategy
    ) external;

    function setQueueWithdrawalBlock(address staker, uint256 nonce) external;

    function getQueueWithdrawalBlock(address staker, uint256 nonce) external returns (uint256);

    function setFunctionSelectorName(
        bytes4 functionSelector,
        string memory _name
    ) external returns (string memory);

    function getFunctionSelectorName(bytes4 functionSelector) external returns (string memory);

    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) external;

    function getGasLimitForFunctionSelector(bytes4 functionSelector) external returns (uint256);
}