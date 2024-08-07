// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


struct EigenlayerDepositMessage {
    bytes4 functionSelector;
    uint256 amount;
    address staker;
}

struct EigenlayerDepositWithSignatureMessage {
    // bytes4 functionSelector;
    uint256 expiry;
    address strategy;
    address token;
    uint256 amount;
    address staker;
    bytes signature;
}

event EigenlayerDepositParams(
    bytes4 indexed functionSelector,
    uint256 indexed amount,
    address indexed staker
);

event EigenlayerDepositWithSignatureParams(
    bytes4 indexed functionSelector,
    uint256 indexed amount,
    address indexed staker
);

interface IRestakingConnector {

    function getStrategy() external returns (IStrategy);

    function getStrategyManager() external returns (IStrategyManager);

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

    function decodeDepositMessage(
        bytes calldata message
    ) external returns (EigenlayerDepositMessage memory);

    function decodeDepositWithSignatureMessage(
        bytes memory message
    ) external returns (EigenlayerDepositWithSignatureMessage memory);
}