// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {console} from "forge-std/Test.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Adminable} from "./utils/Adminable.sol";
import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {EigenlayerMsgDecoders} from "./utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "./utils/EigenlayerMsgEncoders.sol";



contract RestakingConnector is IRestakingConnector, EigenlayerMsgDecoders, Adminable {

    IDelegationManager public delegationManager;
    IStrategyManager public strategyManager;
    IStrategy public strategy;

    error AddressNull();

    constructor() {
        __Adminable_init();
    }

    function getEigenlayerContracts() public view returns (
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

}