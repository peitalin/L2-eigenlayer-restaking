// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Adminable} from "./utils/Adminable.sol";
import {IRestakingConnector, MsgForEigenlayer} from "./IRestakingConnector.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract RestakingConnector is IRestakingConnector, Adminable {

    IDelegationManager public delegationManager;
    IStrategyManager public strategyManager;
    IStrategy public strategy;

    error AddressNull();

    mapping(address => mapping(address => uint256)) public stakerToAmount;

    constructor() {
        __Adminable_init();
    }

    event EigenlayerContractCallParams(
        bytes4 indexed functionSelector,
        uint256 indexed amount,
        address indexed staker
    );

    function getEigenlayerContracts() public returns (
        IDelegationManager,
        IStrategyManager,
        IStrategy
    ){
        return (delegationManager, strategyManager, strategy);
    }

    function setEigenlayerContracts(
        IDelegationManager _delegationManager,
        IStrategyManager _strategyManager,
        IStrategy _strategy
    ) public onlyAdminOrOwner {

        if (address(_delegationManager) == address(0)) revert AddressNull();
        if (address(_strategyManager) == address(0)) revert AddressNull();
        if (address(_strategy) == address(0)) revert AddressNull();

        delegationManager = _delegationManager;
        strategyManager = _strategyManager;
        strategy = _strategy;
    }

    function getStrategy() public view returns (IStrategy) {
        return strategy;
    }

    function getStrategyManager() public view returns (IStrategyManager) {
        return strategyManager;
    }

    function decodeMessageForEigenlayer(bytes memory message) public returns (MsgForEigenlayer memory) {

        bytes32 var1;
        bytes32 var2;
        bytes4 functionSelector;
        uint256 amount;
        address staker;

        assembly {
            var1 := mload(add(message, 32))
            var2 := mload(add(message, 64))
            functionSelector := mload(add(message, 96))
            amount := mload(add(message, 100))
            staker := mload(add(message, 132))
        }

        MsgForEigenlayer memory msgForEigenlayer = MsgForEigenlayer({
            functionSelector: functionSelector,
            amount: amount,
            staker: staker
        });

        // check if address has existing deposit
        stakerToAmount[staker][address(strategy)] += amount;

        emit EigenlayerContractCallParams(
            msgForEigenlayer.functionSelector,
            msgForEigenlayer.amount,
            msgForEigenlayer.staker
        );

        return msgForEigenlayer;
    }

}