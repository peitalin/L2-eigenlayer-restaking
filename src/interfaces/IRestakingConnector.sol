// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IEigenlayerMsgDecoders} from "../interfaces/IEigenlayerMsgDecoders.sol";


interface IRestakingConnector is IEigenlayerMsgDecoders {

    function decodeFunctionSelector(bytes memory message) external returns (bytes4);

    function encodeTransferToStakerMsg(bytes32 withdrawalRoot) external returns (bytes memory);

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

}