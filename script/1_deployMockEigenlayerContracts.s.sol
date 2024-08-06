// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";

import {PauserRegistry} from "eigenlayer-contracts/src/contracts/permissions/PauserRegistry.sol";
import {StrategyManager} from  "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";
import {DelegationManager} from "eigenlayer-contracts/src/contracts/core/DelegationManager.sol";
import {RewardsCoordinator} from "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";

import {MockERC20Strategy} from "../src/MockERC20Strategy.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract DeployMockEigenlayerContractsScript is Script {

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address public deployer = vm.addr(deployerKey);

    mapping(uint256 => string) public chains;
    IERC20 public mockERC20;

    // RewardsCoordinator Parameters. TBD what they should be for Treasure chain
    uint32 public CALCULATION_INTERVAL_SECONDS = 604800; // 7 days
    uint32 public MAX_REWARDS_DURATION = 7257600; // 84 days
    uint32 public MAX_RETROACTIVE_LENGTH = 0; // 0 days // must be zero or reverts on anvil localhost
    uint32 public MAX_FUTURE_LENGTH = 2419200; // 28 days
    uint32 public GENESIS_REWARDS_TIMESTAMP = 0;

    uint256 public USER_DEPOSIT_LIMIT = 10 * 1e18;  // uint256 _maxPerDeposit,
    uint256 public TOTAL_DEPOSIT_LIMIT = 10 * 1e18; // uint256 _maxTotalDeposits,

    function run() public returns (
        IStrategyManager,
        IPauserRegistry,
        IRewardsCoordinator,
        IDelegationManager,
        IStrategy
    ) {

        IStrategyManager strategyManager;
        IPauserRegistry pauserRegistry;
        IRewardsCoordinator rewardsCoordinator;
        IDelegationManager delegationManager;

        if (block.chainid != 31337 && block.chainid != 11155111) revert("must deploy on Eth or local network");

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        ProxyAdmin proxyAdmin = deployProxyAdmin();

        (
            strategyManager,
            pauserRegistry,
            rewardsCoordinator,
            delegationManager
        ) = deployEigenlayerContracts(proxyAdmin);

        if (block.chainid == 31337) {
            // can mint in localhost tests
            mockERC20 = deployMockERC20("Mock MAGIC", "MMAGIC", proxyAdmin);
        } else {
            // CCIP BnM Token on ETH Sepolia
            // can't mint, you need to transfer CCIP-BnM tokens to receiver contract
            mockERC20 = IERC20(0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05);
            // mockERC20 = ccipBnM;
        }

        IStrategy strategy = IStrategy(deployERC20Strategy(
            strategyManager,
            pauserRegistry,
            mockERC20,
            proxyAdmin
        ));

        saveContractAddresses(
            address(strategyManager),
            address(pauserRegistry),
            address(rewardsCoordinator),
            address(delegationManager),
            address(strategy)
        );

        whitelistStrategy(strategyManager, strategy);

        return (
            strategyManager,
            pauserRegistry,
            rewardsCoordinator,
            delegationManager,
            strategy
        );
    }

    function readSavedEigenlayerAddresses() public returns (
        IStrategyManager,
        IPauserRegistry,
        IRewardsCoordinator,
        IDelegationManager,
        IStrategy
    ) {

        chains[31337] = "localhost";
        chains[17000] = "holesky";
        chains[421614] = "arbsepolia";
        chains[11155111] = "ethsepolia";

        IRewardsCoordinator rewardsCoordinator;
        IPauserRegistry pauserRegistry;
        IDelegationManager delegationManager;
        IStrategyManager strategyManager;
        IStrategy strategy;

        string memory inputPath = string(abi.encodePacked("script/", chains[block.chainid], "/eigenLayerContracts.config.json"));
        string memory deploymentData = vm.readFile(inputPath);

        strategyManager = IStrategyManager(stdJson.readAddress(deploymentData, ".addresses.strategyManager"));
        pauserRegistry = IPauserRegistry(stdJson.readAddress(deploymentData, ".addresses.pauserRegistry"));
        rewardsCoordinator = IRewardsCoordinator(stdJson.readAddress(deploymentData, ".addresses.rewardsCoordinator"));
        delegationManager = IDelegationManager(stdJson.readAddress(deploymentData, ".addresses.delegationManager"));
        strategy = IStrategy(stdJson.readAddress(deploymentData, ".addresses.strategies.CCIPStrategy"));

        return (strategyManager, pauserRegistry, rewardsCoordinator, delegationManager, strategy);
    }

    function deployEigenlayerContracts(ProxyAdmin proxyAdmin) public returns (
        IStrategyManager,
        IPauserRegistry,
        IRewardsCoordinator,
        IDelegationManager
    ) {
        vm.startBroadcast(deployer);

        IDelegationManager delegationManager;
        ISlasher slasher;
        IEigenPodManager eigenPodManager;
        StrategyManager strategyManager;

        address[] memory pausers = new address[](1);
        pausers[0] = deployer;
        PauserRegistry _pauserRegistry = new PauserRegistry(pausers, deployer);

        EmptyContract emptyContract = new EmptyContract();

        strategyManager = StrategyManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        );

        delegationManager = new DelegationManager(
            strategyManager,
            slasher,
            eigenPodManager
        );

        StrategyManager strategyManagerImpl = new StrategyManager(
            delegationManager,
            eigenPodManager,
            slasher
        );

        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(strategyManager))),
            address(strategyManagerImpl),
            abi.encodeWithSelector(
                StrategyManager.initialize.selector,
                deployer, // initialOwner,
                deployer, // initialStrategyWhitelister,
                _pauserRegistry,
                0 // initialPauseStaus
            )
        );

        RewardsCoordinator rewardsCoordinator = new RewardsCoordinator(
            delegationManager,
            strategyManager,
            CALCULATION_INTERVAL_SECONDS ,
            MAX_REWARDS_DURATION,
            MAX_RETROACTIVE_LENGTH ,
            MAX_FUTURE_LENGTH,
            GENESIS_REWARDS_TIMESTAMP
        );

        rewardsCoordinator = RewardsCoordinator(
            address(
                new TransparentUpgradeableProxy(
                    address(rewardsCoordinator),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        RewardsCoordinator.initialize.selector,
                        deployer, // initialOwner
                        _pauserRegistry,
                        0, // initialPausedStatus
                        deployer, // rewardsUpdater
                        0, // activation delay
                        0 // global commission Bips
                    )
                )
            )
        );

        vm.stopBroadcast();

        return (
            IStrategyManager(address(strategyManager)),
            IPauserRegistry(address(_pauserRegistry)),
            IRewardsCoordinator(address(rewardsCoordinator)),
            IDelegationManager(address(delegationManager))
        );
    }

    function deployProxyAdmin() public returns (ProxyAdmin) {
        vm.startBroadcast(deployer);
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        vm.stopBroadcast();
        return proxyAdmin;
    }

    function deployMockERC20(
        string memory name,
        string memory symbol,
        ProxyAdmin proxyAdmin
    ) public returns (IERC20) {

        vm.startBroadcast(deployer);

        MockERC20 erc20impl = new MockERC20();

        MockERC20 erc20proxy = MockERC20(
            address(
                new TransparentUpgradeableProxy(
                    address(erc20impl),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        MockERC20.initialize.selector,
                        name,
                        symbol
                    )
                )
            )
        );

        vm.stopBroadcast();
        return IERC20(address(erc20proxy));
    }

    function deployERC20Strategy(
        IStrategyManager _strategyManager,
        IPauserRegistry _pauserRegistry,
        IERC20 _mockERC20,
        ProxyAdmin proxyAdmin
    ) public returns (MockERC20Strategy) {

        vm.startBroadcast(deployer);

        require(address(_mockERC20) != address(0), "mockERC20 cannot be address(0)");
        require(address(_strategyManager) != address(0), "strategyManager cannot be address(0)");
        require(address(_pauserRegistry) != address(0), "pauserRegistry cannot be address(0)");

        MockERC20Strategy strategyImpl = new MockERC20Strategy(_strategyManager);

        MockERC20Strategy strategyProxy = MockERC20Strategy(
            address(
                new TransparentUpgradeableProxy(
                    address(strategyImpl),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        MockERC20Strategy.initialize.selector,
                        USER_DEPOSIT_LIMIT,  // uint256 _maxPerDeposit,
                        TOTAL_DEPOSIT_LIMIT, // uint256 _maxTotalDeposits,
                        _mockERC20,          // IERC20 _underlyingToken,
                        _pauserRegistry      // IPauserRegistry _pauserRegistry
                    )
                )
            )
        );

        vm.stopBroadcast();

        return strategyProxy;
    }

    function whitelistStrategy(
        IStrategyManager strategyManager,
        IStrategy strategy
    ) public {
        IStrategy[] memory strategiesToWhitelist = new IStrategy[](1);
        bool[] memory thirdPartyTransfersForbiddenValues = new bool[](1);

        strategiesToWhitelist[0] = strategy;
        thirdPartyTransfersForbiddenValues[0] = true;

        vm.startBroadcast(deployer);
        strategyManager.addStrategiesToDepositWhitelist(strategiesToWhitelist, thirdPartyTransfersForbiddenValues);
        vm.stopBroadcast();
    }

    function saveContractAddresses(
        address strategyManager,
        address pauserRegistry,
        address rewardsCoordinator,
        address delegationManager,
        address strategy
    ) public {

        /////////////////////////////////////////////////
        // { "addresses": <addresses_output>}
        /////////////////////////////////////////////////
        string memory keyAddresses = "addresses";
        vm.serializeAddress(keyAddresses, "strategyManager", strategyManager);
        vm.serializeAddress(keyAddresses, "pauserRegistry", pauserRegistry);
        vm.serializeAddress(keyAddresses, "rewardsCoordinator", rewardsCoordinator);
        vm.serializeAddress(keyAddresses, "delegationManager", delegationManager);
        // vm.serializeAddress(keyAddresses, "proxyAdmin", proxyAdmin);

        /////////////////////////////////////////////////
        // { "addresses": { "strategies": <strategies_output>}}
        /////////////////////////////////////////////////
        string memory keyStrategies = "strategies";
        string memory strategies_output = vm.serializeAddress(
            keyStrategies,
            "CCIPStrategy",
            strategy
        );
        string memory addresses_output = vm.serializeString(
            keyAddresses,
            keyStrategies,
            strategies_output
        );

        /////////////////////////////////////////////////
        // { "parameters": <parameters_output>}
        /////////////////////////////////////////////////
        string memory keyParameters = "parameters";
        string memory parameters_output = vm.serializeAddress(keyParameters, "deployer", deployer);

        /////////////////////////////////////////////////
        // { "chainInfo": <chain_info_output>}
        /////////////////////////////////////////////////
        string memory keyChainInfo = "chainInfo";
        vm.serializeUint(keyChainInfo, "deploymentBlock", block.number);
        string memory chain_info_output = vm.serializeUint(keyChainInfo, "chainId", block.chainid);

        /////////////////////////////////////////////////
        // combine objects to a root object
        /////////////////////////////////////////////////
        string memory root_object = "rootObject";
        vm.serializeString(root_object, keyChainInfo, chain_info_output);
        vm.serializeString(root_object, keyParameters, parameters_output);
        string memory finalJson = vm.serializeString(root_object, keyAddresses, addresses_output);

        chains[31337] = "localhost";
        chains[17000] = "holesky";
        chains[421614] = "arbsepolia";
        chains[11155111] = "ethsepolia";

        string memory finalOutputPath = string(abi.encodePacked(
            "script/",
            chains[block.chainid],
            "/eigenlayerContracts.config.json"
        ));
        vm.writeJson(finalJson, finalOutputPath);
    }
}