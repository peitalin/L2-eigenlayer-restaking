// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategyFactory} from "@eigenlayer-contracts/interfaces/IStrategyFactory.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "@eigenlayer-contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin-v4-contracts/token/ERC20/IERC20.sol";

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

        DeployMockEigenlayerContractsScript.EigenlayerAddresses memory ea =
            deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        vm.assertEq(address(ea.strategy), address(strategy));
        vm.assertEq(address(ea.strategyManager), address(strategyManager));
        vm.assertEq(address(ea.strategyFactory), address(strategyFactory));
        vm.assertEq(address(ea.pauserRegistry), address(pauserRegistry));
        vm.assertEq(address(ea.delegationManager), address(delegationManager));
        vm.assertEq(address(ea.rewardsCoordinator), address(rewardsCoordinator));
        vm.assertEq(address(ea.tokenERC20), address(tokenL1));

        if (address(ea.strategy) == address(0)) {
            revert("Could not read eigenlayer deployment: strategy");
        }
        if (address(ea.strategyManager) == address(0)) {
            revert("Could not read eigenlayer deployment: strategyManager");
        }
        if (address(ea.strategyFactory) == address(0)) {
            revert("Could not read eigenlayer deployment: strategyFactory");
        }
        if (address(ea.pauserRegistry) == address(0)) {
            revert("Could not read eigenlayer deployment: pauserRegistry");
        }
        if (address(ea.delegationManager) == address(0)) {
            revert("Could not read eigenlayer deployment: delegationManager");
        }
        if (address(ea.rewardsCoordinator) == address(0)) {
            revert("Could not read eigenlayer deployment: rewardsCoordinator");
        }
        if (address(ea.tokenERC20) == address(0)) {
            revert("Could not read eigenlayer deployment: tokenL1");
        }
    }
}
