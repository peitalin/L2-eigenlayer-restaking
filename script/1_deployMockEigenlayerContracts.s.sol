// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategyFactory} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyFactory.sol";
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
import {StrategyBase} from  "eigenlayer-contracts/src/contracts/strategies/StrategyBase.sol";
import {StrategyFactory} from "eigenlayer-contracts/src/contracts/strategies/StrategyFactory.sol";

import {MockERC20Strategy} from "../src/MockERC20Strategy.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract DeployMockEigenlayerContractsScript is Script {

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address public deployer = vm.addr(deployerKey);

    mapping(uint256 => string) public chains;

    IERC20 public mockERC20;
    IStrategyManager public strategyManager;
    ISlasher public slasher;
    IEigenPodManager public eigenPodManager;
    IPauserRegistry public pauserRegistry;
    IRewardsCoordinator public rewardsCoordinator;
    IDelegationManager public delegationManager;
    ProxyAdmin public proxyAdmin;

    // RewardsCoordinator Parameters. TBD what they should be for Treasure chain
    uint32 public CALCULATION_INTERVAL_SECONDS = 604800; // 7 days
    uint32 public MAX_REWARDS_DURATION = 7257600; // 84 days
    uint32 public MAX_RETROACTIVE_LENGTH = 0; // 0 days // must be zero or reverts on anvil localhost
    uint32 public MAX_FUTURE_LENGTH = 2419200; // 28 days
    uint32 public GENESIS_REWARDS_TIMESTAMP = 0;

    uint256 public USER_DEPOSIT_LIMIT = 10 * 1e18;  // uint256 _maxPerDeposit,
    uint256 public TOTAL_DEPOSIT_LIMIT = 100 * 1e18; // uint256 _maxTotalDeposits,

    function run() public returns (
        IStrategyManager,
        IPauserRegistry,
        IRewardsCoordinator,
        IDelegationManager,
        IStrategy,
        IERC20
    ) {


        if (block.chainid != 31337 && block.chainid != 11155111) revert("must deploy on Eth or local network");

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        proxyAdmin = deployProxyAdmin();

        (
            strategyManager,
            pauserRegistry,
            rewardsCoordinator,
            delegationManager
        ) = deployEigenlayerContracts(proxyAdmin);

        if (block.chainid == 31337) {
            // can mint in localhost tests
            mockERC20 = IERC20(address(deployMockERC20("Mock MAGIC", "MMAGIC", proxyAdmin)));
        } else {
            // CCIP BnM Token on ETH Sepolia
            // can't mint, you need to transfer CCIP-BnM tokens to receiver contract
            mockERC20 = IERC20(0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05);
            // mockERC20 = ccipBnM;
        }

        StrategyFactory strategyFactory = deployStrategyFactory(
            StrategyManager(address(strategyManager)),
            pauserRegistry,
            proxyAdmin
        );

        // automatically deploys Strategy and whitelist it
        // IStrategy strategy = strategyFactory.deployNewStrategy(mockERC20);

        IStrategy strategy = IStrategy(deployERC20Strategy(
            strategyManager,
            pauserRegistry,
            mockERC20,
            proxyAdmin
        ));

        whitelistStrategy(strategyFactory, strategy);

        writeContractAddresses(
            address(strategy),
            address(strategyManager),
            address(strategyFactory),
            address(pauserRegistry),
            address(delegationManager),
            address(rewardsCoordinator),
            address(proxyAdmin)
        );

        return (
            strategyManager,
            pauserRegistry,
            rewardsCoordinator,
            delegationManager,
            strategy,
            mockERC20
        );
    }

    function deployEigenlayerContracts(ProxyAdmin proxyAdmin) public returns (
        IStrategyManager,
        IPauserRegistry,
        IRewardsCoordinator,
        IDelegationManager
    ) {
        ///////////////////////////////////////////////////
        vm.startBroadcast(deployer);
        ///////////////////////////////////////////////////
        EmptyContract emptyContract = new EmptyContract();

        address[] memory pausers = new address[](1);
        pausers[0] = deployer;
        PauserRegistry _pauserRegistry = new PauserRegistry(pausers, deployer);

        // deploy first to get address for delegationManager
        strategyManager = StrategyManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), ""))
        );
        ///////////////////////////////////////////////////
        vm.stopBroadcast();
        ///////////////////////////////////////////////////

        delegationManager = IDelegationManager(address(
            deployDelegationManager(
                strategyManager,
                slasher,
                eigenPodManager,
                _pauserRegistry
            )
        ));

        ///////////////////////////////////////////////////
        vm.startBroadcast(deployer);
        ///////////////////////////////////////////////////
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
        ///////////////////////////////////////////////////
        vm.stopBroadcast();
        ///////////////////////////////////////////////////

        RewardsCoordinator rewardsCoordinator = deployRewardsCoordinator(
            strategyManager,
            delegationManager,
            _pauserRegistry
        );

        return (
            IStrategyManager(address(strategyManager)),
            IPauserRegistry(address(_pauserRegistry)),
            IRewardsCoordinator(address(rewardsCoordinator)),
            IDelegationManager(address(delegationManager))
        );
    }

    function deployProxyAdmin() public returns (ProxyAdmin) {
        vm.startBroadcast(deployer);
        ProxyAdmin _proxyAdmin = new ProxyAdmin();
        vm.stopBroadcast();
        return _proxyAdmin;
    }

    function deployRewardsCoordinator(
        IStrategyManager _strategyManager,
        IDelegationManager _delegationManager,
        IPauserRegistry _pauserRegistry
    ) internal returns (RewardsCoordinator) {
        vm.startBroadcast(deployer);
        // Eigenlayer disableInitialisers so they must be called via upgradeable proxy
        RewardsCoordinator rewardsCoordinator = new RewardsCoordinator(
            _delegationManager,
            _strategyManager,
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
        return rewardsCoordinator;
    }

    function deployDelegationManager(
        IStrategyManager _strategyManager,
        ISlasher _slasher,
        IEigenPodManager _eigenPodManager,
        IPauserRegistry _pauserRegistry
    ) internal returns (DelegationManager) {
        vm.startBroadcast(deployer);
        // Eigenlayer disableInitialisers so they must be called via upgradeable proxy
        DelegationManager delegationManagerImpl = new DelegationManager(
            _strategyManager,
            _slasher,
            _eigenPodManager
        );

        // IStrategy[] memory _strategies = new IStrategy[](0);
        // uint256[] memory _withdrawalDelayBlocks = new uint256[](0);
         DelegationManager delegationManagerProxy = DelegationManager(
            address(new TransparentUpgradeableProxy(
                address(delegationManagerImpl),
                address(proxyAdmin),
                abi.encodeWithSelector(
                    DelegationManager.initialize.selector,
                    deployer,
                    _pauserRegistry,
                    0, // initialPausedStatus
                    4, // _minWithdrawalDelayBlocks: 4x15 seconds = 1 min
                    new IStrategy[](0), // _strategies
                    new uint256[](0) // _withdrawalDelayBlocks
                )
            ))
        );

        vm.stopBroadcast();
        return delegationManagerProxy;
    }

    function deployStrategyFactory(
        StrategyManager _strategyManager,
        IPauserRegistry _pauserRegistry,
        ProxyAdmin _proxyAdmin
    ) internal returns (StrategyFactory) {
        vm.startBroadcast(deployer);

        EmptyContract emptyContract = new EmptyContract();
        // Create base strategy implementation and deploy a few strategies
        StrategyBase strategyImpl = new StrategyBase(_strategyManager);

        // Create a proxy beacon for base strategy implementation
        UpgradeableBeacon strategyBeacon = new UpgradeableBeacon(address(strategyImpl));

        StrategyFactory strategyFactory = StrategyFactory(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(_proxyAdmin), ""))
        );

        StrategyFactory strategyFactoryImplementation = new StrategyFactory(strategyManager);

        // Strategy Factory, upgrade and initalized
        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(strategyFactory))),
            address(strategyFactoryImplementation),
            abi.encodeWithSelector(
                StrategyFactory.initialize.selector,
                deployer,
                _pauserRegistry,
                0, // initial paused status
                IBeacon(strategyBeacon)
            )
        );

        _strategyManager.setStrategyWhitelister(address(strategyFactory));

        vm.stopBroadcast();
        return strategyFactory;
    }

    function deployMockERC20(
        string memory name,
        string memory symbol,
        ProxyAdmin _proxyAdmin
    ) public returns (MockERC20) {

        vm.startBroadcast(deployer);

        MockERC20 erc20impl = new MockERC20();

        MockERC20 erc20proxy = MockERC20(
            address(
                new TransparentUpgradeableProxy(
                    address(erc20impl),
                    address(_proxyAdmin),
                    abi.encodeWithSelector(
                        MockERC20.initialize.selector,
                        name,
                        symbol
                    )
                )
            )
        );

        vm.stopBroadcast();
        return erc20proxy;
    }

    function deployERC20Strategy(
        IStrategyManager _strategyManager,
        IPauserRegistry _pauserRegistry,
        IERC20 _mockERC20,
        ProxyAdmin _proxyAdmin
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
                    address(_proxyAdmin),
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
        IStrategyFactory _strategyFactory,
        IStrategy _strategy
    ) public {
        IStrategy[] memory strategiesToWhitelist = new IStrategy[](1);
        bool[] memory thirdPartyTransfersForbiddenValues = new bool[](1);

        strategiesToWhitelist[0] = _strategy;
        thirdPartyTransfersForbiddenValues[0] = false;
        // allow third parties to deposit on behalf of a user (with their signature)

        vm.startBroadcast(deployer);
        _strategyFactory.whitelistStrategies(strategiesToWhitelist, thirdPartyTransfersForbiddenValues);
        vm.stopBroadcast();
    }

    function readSavedEigenlayerAddresses() public returns (
        IStrategy,
        IStrategyManager,
        IStrategyFactory,
        IPauserRegistry,
        IDelegationManager,
        IRewardsCoordinator
    ) {

        chains[31337] = "localhost";
        chains[17000] = "holesky";
        chains[421614] = "arbsepolia";
        chains[11155111] = "ethsepolia";

        // Eigenlayer contract addresses are only on EthSepolia and localhost, not L2
        uint256 chainid = 11155111;
        if (block.chainid == 31337) {
            chainid = 31337;
        } else {
            chainid = 11155111;
        }

        IStrategy _strategy;
        IStrategyManager _strategyManager;
        IStrategyFactory _strategyFactory;
        IDelegationManager _delegationManager;
        IRewardsCoordinator _rewardsCoordinator;
        IPauserRegistry _pauserRegistry;

        string memory inputPath = string(abi.encodePacked("script/", chains[chainid], "/eigenLayerContracts.config.json"));
        string memory deploymentData = vm.readFile(inputPath);

        _strategy = IStrategy(stdJson.readAddress(deploymentData, ".addresses.strategies.CCIPStrategy"));
        _strategyManager = IStrategyManager(stdJson.readAddress(deploymentData, ".addresses.StrategyManager"));
        _strategyFactory = IStrategyFactory(stdJson.readAddress(deploymentData, ".addresses.StrategyFactory"));
        _pauserRegistry = IPauserRegistry(stdJson.readAddress(deploymentData, ".addresses.PauserRegistry"));
        _delegationManager = IDelegationManager(stdJson.readAddress(deploymentData, ".addresses.DelegationManager"));
        _rewardsCoordinator = IRewardsCoordinator(stdJson.readAddress(deploymentData, ".addresses.RewardsCoordinator"));

        return (
            _strategy,
            _strategyManager,
            _strategyFactory,
            _pauserRegistry,
            _delegationManager,
            _rewardsCoordinator
        );
    }

    function writeContractAddresses(
        address _strategy,
        address _strategyManager,
        address _strategyFactory,
        address _pauserRegistry,
        address _delegationManager,
        address _rewardsCoordinator,
        address _proxyAdmin
    ) public {

        /////////////////////////////////////////////////
        // { "addresses": <addresses_output>}
        /////////////////////////////////////////////////
        string memory keyAddresses = "addresses";
        vm.serializeAddress(keyAddresses, "StrategyManager", _strategyManager);
        vm.serializeAddress(keyAddresses, "StrategyFactory", _strategyFactory);
        vm.serializeAddress(keyAddresses, "PauserRegistry", _pauserRegistry);
        vm.serializeAddress(keyAddresses, "RewardsCoordinator", _rewardsCoordinator);
        vm.serializeAddress(keyAddresses, "DelegationManager", _delegationManager);
        vm.serializeAddress(keyAddresses, "ProxyAdmin", _proxyAdmin);

        /////////////////////////////////////////////////
        // { "addresses": { "strategies": <strategies_output>}}
        /////////////////////////////////////////////////
        string memory keyStrategies = "strategies";
        string memory strategies_output = vm.serializeAddress(
            keyStrategies,
            "CCIPStrategy",
            _strategy
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