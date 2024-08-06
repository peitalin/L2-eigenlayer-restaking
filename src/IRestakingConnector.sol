// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";


struct MsgForEigenlayer {
    bytes4 functionSelector;
    uint256 amount;
    address staker;
}

interface IRestakingConnector {

    function getStrategy() external returns (IStrategy);

    function getStrategyManager() external returns (IStrategyManager);

    function decodeMessageForEigenlayer(
        bytes calldata message
    ) external returns (MsgForEigenlayer memory);

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
}