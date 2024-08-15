// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";


contract DeployEigenlayerContractsTest is Test {

    uint256 public deployerKey;
    address public deployer;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    function setUp() public {
		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
    }

    ///// Note: overwrites ethsepolia Eigenlayer contract deployment addresses
    ///// due to vm.forkSelect(). We won't need this as Eigenlayer contracts are
    ///// already deployed.

    // function test_DeployEigenlayerContractsScript() public {
    //     (
    //         IStrategyManager strategyManager,
    //         IPauserRegistry pauserRegistry,
    //         IRewardsCoordinator rewardsCoordinator,
    //         IDelegationManager delegationManager,
    //         IStrategy strategy,
    //         IERC20 token
    //     ) = deployMockEigenlayerContractsScript.run();
    // }

    //     (IStrategy _strategy,,,,,) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

    //     if (address(_strategy) == address(0)) {
    //         console.log("chain: ", block.chainid);
    //         revert("could not read eigenlayer deployments");
    //     }
    // }
}
