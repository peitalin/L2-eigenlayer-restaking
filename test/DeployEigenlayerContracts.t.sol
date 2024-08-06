// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {MockERC20Strategy} from "../src/MockERC20Strategy.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract DeployEigenlayerContractsTest is Test {

    uint256 public deployerKey;
    address public deployer;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
    }

    function test_DeployEigenlayerContractsScript() public {
        deployMockEigenlayerContractsScript.run();
    }

    function test_ReadEigenlayerContractsScript() public {
        (
            ,
            ,
            ,
            ,
            IStrategy _strategy
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();
        if (address(_strategy) == address(0)) {
            console.log("chain: ", block.chainid);
            revert("could not read eigenlayer deployments");
        }
    }

    function test_DeployEigenlayerContracts() public {

        IStrategyManager strategyManager;
        IPauserRegistry pauserRegistry;
        IRewardsCoordinator rewardsCoordinator;
        IDelegationManager delegationManager;

        ProxyAdmin proxyAdmin = deployMockEigenlayerContractsScript.deployProxyAdmin();

        (
            strategyManager,
            pauserRegistry,
            rewardsCoordinator,
            delegationManager
        ) = deployMockEigenlayerContractsScript.deployEigenlayerContracts(proxyAdmin);

        // CCIP BnM Token on ETH Sepolia
        // IERC20 ccipBnM = IERC20(0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05);
        // IERC20 mockERC20 = ccipBnM;
        IERC20 mockERC20 = deployMockEigenlayerContractsScript.deployMockERC20(
            "Mock Magic",
            "MMAGIC",
            proxyAdmin
        );

        IStrategy strategy = IStrategy(deployMockEigenlayerContractsScript.deployERC20Strategy(
            strategyManager,
            pauserRegistry,
            mockERC20,
            proxyAdmin
        ));

        deployMockEigenlayerContractsScript.whitelistStrategy(strategyManager, strategy);
    }
}
