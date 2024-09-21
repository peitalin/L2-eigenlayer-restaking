// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";

import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategyFactory} from "@eigenlayer-contracts/interfaces/IStrategyFactory.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "@eigenlayer-contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";


contract ScriptsTests_ReadEigenlayerContracts is Test {

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    function setUp() public {

        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        vm.chainId(31337);
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_ReadEigenlayerContractsScript() public {

        (
            IStrategy strategy,
            IStrategyManager strategyManager,
            IStrategyFactory strategyFactory,
            IPauserRegistry pauserRegistry,
            IDelegationManager delegationManager,
            IRewardsCoordinator rewardsCoordinator,
            IERC20 tokenL1
        ) = deployMockEigenlayerContractsScript.run();

        (
            IStrategy _strategy,
            IStrategyManager _strategyManager,
            IStrategyFactory _strategyFactory,
            IPauserRegistry _pauserRegistry,
            IDelegationManager _delegationManager,
            IRewardsCoordinator _rewardsCoordinator,
            IERC20 _tokenL1
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        vm.assertEq(address(strategy), address(_strategy));
        vm.assertEq(address(strategyManager), address(_strategyManager));
        vm.assertEq(address(strategyFactory), address(_strategyFactory));
        vm.assertEq(address(pauserRegistry), address(_pauserRegistry));
        vm.assertEq(address(delegationManager), address(_delegationManager));
        vm.assertEq(address(rewardsCoordinator), address(_rewardsCoordinator));
        vm.assertEq(address(tokenL1), address(_tokenL1));

        if (address(_strategy) == address(0)) {
            revert("Could not read eigenlayer deployment: strategy");
        }
        if (address(_strategyManager) == address(0)) {
            revert("Could not read eigenlayer deployment: strategyManager");
        }
        if (address(_strategyFactory) == address(0)) {
            revert("Could not read eigenlayer deployment: strategyFactory");
        }
        if (address(_pauserRegistry) == address(0)) {
            revert("Could not read eigenlayer deployment: pauserRegistry");
        }
        if (address(_delegationManager) == address(0)) {
            revert("Could not read eigenlayer deployment: delegationManager");
        }
        if (address(_rewardsCoordinator) == address(0)) {
            revert("Could not read eigenlayer deployment: rewardsCoordinator");
        }
        if (address(_tokenL1) == address(0)) {
            revert("Could not read eigenlayer deployment: tokenL1");
        }
    }
}
