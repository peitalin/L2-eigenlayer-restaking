// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, stdJson} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-v4-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin-v4-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-v4-contracts/proxy/transparent/ProxyAdmin.sol";
import {IBeacon} from "@openzeppelin-v4-contracts/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-v4-contracts/proxy/beacon/UpgradeableBeacon.sol";

import {IETHPOSDeposit} from "@eigenlayer-contracts/interfaces/IETHPOSDeposit.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategyFactory} from "@eigenlayer-contracts/interfaces/IStrategyFactory.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "@eigenlayer-contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IEigenPodManager} from "@eigenlayer-contracts/interfaces/IEigenPodManager.sol";
import {IAllocationManager} from "@eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IPermissionController} from "@eigenlayer-contracts/interfaces/IPermissionController.sol";

import {AllocationManager} from "@eigenlayer-contracts/core/AllocationManager.sol";
import {PermissionController} from "@eigenlayer-contracts/permissions/PermissionController.sol";
import {PauserRegistry} from "@eigenlayer-contracts/permissions/PauserRegistry.sol";
import {StrategyManager} from  "@eigenlayer-contracts/core/StrategyManager.sol";
import {DelegationManager} from "@eigenlayer-contracts/core/DelegationManager.sol";
import {RewardsCoordinator} from "@eigenlayer-contracts/core/RewardsCoordinator.sol";
import {EigenPodManager} from "@eigenlayer-contracts/pods/EigenPodManager.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";
import {StrategyBase} from  "@eigenlayer-contracts/strategies/StrategyBase.sol";
import {StrategyFactory} from "@eigenlayer-contracts/strategies/StrategyFactory.sol";
import {StrategyBaseTVLLimits} from "@eigenlayer-contracts/strategies/StrategyBaseTVLLimits.sol";

import {ERC20Minter} from "../test/mocks/ERC20Minter.sol";
import {IERC20} from "@openzeppelin-v4-contracts/token/ERC20/IERC20.sol";
import {IBurnMintERC20} from "@chainlink/shared/token/ERC20/IBurnMintERC20.sol";
import {EthSepolia} from "./Addresses.sol";


// @dev must match EIGENLAYER_VERSION in EigenAgent6551.sol
string constant EIGENLAYER_VERSION = "v1.3.0";
// forge install git@github.com/Layr-Labs/eigenlayer-contracts@v1.3.0

/// @dev This deploys mock Eigenlayer contracts from the `dev` branch for the purpose
/// of testing deposits, withdrawals, and delegation with custom ERC20 strategies only.
/// It does not deploy and configure EigenPod and Slashing features (can add later).
contract DeployMockEigenlayerContractsScript is Script {

    uint256 private deployerKey = vm.envUint("DEPLOYER_KEY");
    address public deployer = vm.addr(deployerKey);

    mapping(uint256 => string) public chains;

    IERC20 public tokenERC20;
    IStrategyManager public strategyManager;
    IStrategyManager public strategyManagerProxy;
    IPauserRegistry public pauserRegistry;
    IRewardsCoordinator public rewardsCoordinator;
    IDelegationManager public delegationManager;
    AllocationManager public allocationManager;
    IAllocationManager public allocationManagerProxy;
    IPermissionController public permissionController;
    ProxyAdmin public proxyAdmin;
    EmptyContract public emptyContract;

    // RewardsCoordinator Parameters. TBD what they should be
    uint32 public CALCULATION_INTERVAL_SECONDS = 604800; // 7 days
    uint32 public MAX_REWARDS_DURATION = 7257600; // 84 days
    uint32 public MAX_RETROACTIVE_LENGTH = 0; // 0 days // must be zero or reverts on anvil localhost
    uint32 public MAX_FUTURE_LENGTH = 2419200; // 28 days
    uint32 public GENESIS_REWARDS_TIMESTAMP = 0;

    uint256 public USER_DEPOSIT_LIMIT = 100_000 ether;  // uint256 _maxPerDeposit,
    uint256 public TOTAL_DEPOSIT_LIMIT = 10_000_000 ether; // uint256 _maxTotalDeposits,

    uint32 public MIN_WITHDRAWAL_DELAY = 10;
    uint32 public DEALLOCATION_DELAY = MIN_WITHDRAWAL_DELAY;
    uint32 public ALLOCATION_CONFIGURATION_DELAY = 10;

    function run() public returns (
        IStrategy,
        IStrategyManager,
        IStrategyFactory,
        IPauserRegistry,
        IDelegationManager,
        IRewardsCoordinator,
        IERC20
    ) {
        bool saveDeployedContracts = true;
        return deployEigenlayerContracts(saveDeployedContracts);
    }

    function deployEigenlayerContracts(bool saveDeployedContracts) public returns (
        IStrategy,
        IStrategyManager,
        IStrategyFactory,
        IPauserRegistry,
        IDelegationManager,
        IRewardsCoordinator,
        IERC20
    ) {
        if (block.chainid != 31337 && block.chainid != 11155111 && block.chainid != 17000)
            revert("must deploy on Eth Sepolia, Holesky or local network");

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployer);
        proxyAdmin = new ProxyAdmin();
        emptyContract = new EmptyContract();
        vm.stopBroadcast();

        (
            strategyManager,
            pauserRegistry,
            delegationManager,
            allocationManagerProxy,
            rewardsCoordinator
        ) = _deployEigenlayerCoreContracts(proxyAdmin);

        if (
            block.chainid != 11155111 // EthSepolia
        ) {
            tokenERC20 = IERC20(address(deployERC20Minter("Local MAGIC", "LMAGIC", proxyAdmin)));
        } else {
            tokenERC20 = IERC20(EthSepolia.BridgeToken);
        }

        IStrategyFactory strategyFactory = _deployStrategyFactory(
            StrategyManager(address(strategyManager)),
            pauserRegistry,
            emptyContract,
            proxyAdmin
        );

        vm.startBroadcast(deployer);
        IStrategy strategy = strategyFactory.deployNewStrategy(tokenERC20);
        vm.stopBroadcast();

        if (saveDeployedContracts) {
            // only when deploying
            writeContractAddresses(
                address(strategy),
                address(strategyManager),
                address(strategyFactory),
                address(pauserRegistry),
                address(delegationManager),
                address(allocationManagerProxy),
                address(rewardsCoordinator),
                address(tokenERC20),
                address(proxyAdmin)
            );
        }

        return (
            strategy,
            strategyManager,
            strategyFactory,
            pauserRegistry,
            delegationManager,
            rewardsCoordinator,
            tokenERC20
        );
    }

    function _deployEigenlayerCoreContracts(ProxyAdmin _proxyAdmin) internal returns (
        IStrategyManager,
        IPauserRegistry,
        IDelegationManager,
        IAllocationManager,
        IRewardsCoordinator
    ) {
        vm.startBroadcast(deployer);
        address[] memory pausers = new address[](1);
        pausers[0] = deployer;
        pauserRegistry = new PauserRegistry(pausers, deployer);

        // deploy first to get address for delegationManager
        strategyManagerProxy = StrategyManager(address(
            new TransparentUpgradeableProxy(address(emptyContract), address(_proxyAdmin), "")
        ));
        // deploy first to get address for delegationManager
        allocationManagerProxy = AllocationManager(address(
            new TransparentUpgradeableProxy(address(emptyContract), address(_proxyAdmin), "")
        ));
        vm.stopBroadcast();

        permissionController = IPermissionController(address(new PermissionController(EIGENLAYER_VERSION)));

        delegationManager = IDelegationManager(address(
            _deployDelegationManager(
                strategyManagerProxy,
                allocationManagerProxy,
                pauserRegistry,
                permissionController,
                _proxyAdmin
            )
        ));

        allocationManager = _deployAllocationManager(
            allocationManagerProxy,
            delegationManager,
            pauserRegistry,
            permissionController,
            _proxyAdmin
        );

        // Check DelegationManager and AllocationManager have same withdrawal/deallocation delay
        require(
            delegationManager.minWithdrawalDelayBlocks() == allocationManager.DEALLOCATION_DELAY(),
            "DelegationManager and AllocationManager have different withdrawal/deallocation delays"
        );
        // require(allocationManager.DEALLOCATION_DELAY() == 1 days);
        // require(allocationManager.ALLOCATION_CONFIGURATION_DELAY() == 10 minutes);

        bytes memory version = bytes(EIGENLAYER_VERSION);
        bytes memory version2 = bytes(delegationManager.version());
        require(version[0] == version2[0], "version mismatch");
        require(version[1] == version2[1], "version mismatch");
        // function _majorVersion() internal view returns (string memory) {
        //     bytes memory v = bytes(_VERSION.toString());
        //     return string(bytes.concat(v[0], v[1]));
        // }

        vm.startBroadcast(deployer);
        StrategyManager strategyManagerImpl = new StrategyManager(
            delegationManager,
            pauserRegistry,
            EIGENLAYER_VERSION
        );
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(strategyManagerProxy))),
            address(strategyManagerImpl),
            abi.encodeWithSelector(
                StrategyManager.initialize.selector,
                deployer, // initialOwner,
                deployer, // initialStrategyWhitelister,
                0 // initialPauseStaus
            )
        );
        vm.stopBroadcast();

        rewardsCoordinator = _deployRewardsCoordinator(
            strategyManagerProxy,
            delegationManager,
            pauserRegistry,
            allocationManagerProxy,
            permissionController
        );

        return (
            IStrategyManager(address(strategyManagerProxy)),
            IPauserRegistry(address(pauserRegistry)),
            IDelegationManager(address(delegationManager)),
            IAllocationManager(address(allocationManagerProxy)),
            IRewardsCoordinator(address(rewardsCoordinator))
        );
    }

    function _deployRewardsCoordinator(
        IStrategyManager _strategyManager,
        IDelegationManager _delegationManager,
        IPauserRegistry _pauserRegistry,
        IAllocationManager _allocationManager,
        IPermissionController _permissionController
    ) internal returns (IRewardsCoordinator) {
        vm.startBroadcast(deployer);
        // Eigenlayer disableInitialisers so they must be called via upgradeable proxy

        /**
         * @notice Parameters for the RewardsCoordinator constructor
         * @param delegationManager The address of the DelegationManager contract
         * @param strategyManager The address of the StrategyManager contract
         * @param allocationManager The address of the AllocationManager contract
         * @param pauserRegistry The address of the PauserRegistry contract
         * @param permissionController The address of the PermissionController contract
         * @param CALCULATION_INTERVAL_SECONDS The interval at which rewards are calculated
         * @param MAX_REWARDS_DURATION The maximum duration of a rewards submission
         * @param MAX_RETROACTIVE_LENGTH The maximum retroactive length of a rewards submission
         * @param MAX_FUTURE_LENGTH The maximum future length of a rewards submission
         * @param GENESIS_REWARDS_TIMESTAMP The timestamp at which rewards are first calculated
         * @param version The semantic version of the contract (e.g. "v1.2.3")
         * @dev Needed to avoid stack-too-deep errors
         */
        IRewardsCoordinatorTypes.RewardsCoordinatorConstructorParams memory rewardsCoordinatorConstructorParams =
            IRewardsCoordinatorTypes.RewardsCoordinatorConstructorParams({
                delegationManager: _delegationManager,
                strategyManager: _strategyManager,
                allocationManager: _allocationManager,
                pauserRegistry: _pauserRegistry,
                permissionController: _permissionController,
                CALCULATION_INTERVAL_SECONDS: CALCULATION_INTERVAL_SECONDS,
                MAX_REWARDS_DURATION: MAX_REWARDS_DURATION,
                MAX_RETROACTIVE_LENGTH: MAX_RETROACTIVE_LENGTH,
                MAX_FUTURE_LENGTH: MAX_FUTURE_LENGTH,
                GENESIS_REWARDS_TIMESTAMP: GENESIS_REWARDS_TIMESTAMP,
                version: EIGENLAYER_VERSION
            });

        RewardsCoordinator rewardsCoordinatorImpl = new RewardsCoordinator(
            rewardsCoordinatorConstructorParams
        );

        IRewardsCoordinator _rewardsCoordinator = IRewardsCoordinator(
            address(
                new TransparentUpgradeableProxy(
                    address(rewardsCoordinatorImpl),
                    address(proxyAdmin), // OZv4 uses ProxyAdmin
                    abi.encodeWithSelector(
                        RewardsCoordinator.initialize.selector,
                        deployer, // initialOwner
                        0, // initialPausedStatus
                        deployer, // rewardsUpdater
                        0, // activation delay
                        0 // defaul split of commission Bips
                    )
                )
            )
        );

        vm.stopBroadcast();
        return _rewardsCoordinator;
    }

    function _deployAllocationManager(
        IAllocationManager _allocationManagerProxy,
        IDelegationManager _delegationManager,
        IPauserRegistry _pauserRegistry,
        IPermissionController _permissionController,
        ProxyAdmin _proxyAdmin
    ) internal returns (AllocationManager) {
        vm.startBroadcast(deployer);

        AllocationManager allocationManagerImpl = new AllocationManager(
            _delegationManager,
            _pauserRegistry,
            _permissionController,
            DEALLOCATION_DELAY, // uint32 _DEALLOCATION_DELAY,
            ALLOCATION_CONFIGURATION_DELAY, // uint32 _ALLOCATION_CONFIGURATION_DELAY,
            EIGENLAYER_VERSION
        );
        _proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(_allocationManagerProxy))),
            address(allocationManagerImpl),
            abi.encodeWithSelector(
                AllocationManager.initialize.selector,
                deployer, // initialOwner
                0 // initialPausedStatus
            )
        );

        vm.stopBroadcast();
        return AllocationManager(address(allocationManagerProxy));
    }

    function _deployDelegationManager(
        IStrategyManager _strategyManager,
        IAllocationManager _allocationManager,
        IPauserRegistry _pauserRegistry,
        IPermissionController _permissionController,
        ProxyAdmin _proxyAdmin
    ) internal returns (DelegationManager) {
        vm.startBroadcast(deployer);

        // deploy first to get address for delegationManager
        DelegationManager delegationManagerProxy = DelegationManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(_proxyAdmin), ""))
        );

        IEigenPodManager eigenPodManager = IEigenPodManager(address(
            new EigenPodManager(
                IETHPOSDeposit(vm.addr(0xee01)),
                IBeacon(vm.addr(0xee02)),
                delegationManagerProxy,
                _pauserRegistry,
                EIGENLAYER_VERSION
            )
        ));

        // Eigenlayer disableInitialisers so they must be called via upgradeable proxy
        DelegationManager delegationManagerImpl = new DelegationManager(
            _strategyManager,
            eigenPodManager,
            _allocationManager,
            _pauserRegistry,
            _permissionController,
            MIN_WITHDRAWAL_DELAY,
            EIGENLAYER_VERSION
        );

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(delegationManagerProxy))),
            address(delegationManagerImpl),
            abi.encodeWithSelector(
                DelegationManager.initialize.selector,
                deployer, // initialOwner
                0 // initialPausedStatus
            )
        );

        vm.stopBroadcast();
        return delegationManagerProxy;
    }

    function _deployStrategyFactory(
        StrategyManager _strategyManager,
        IPauserRegistry _pauserRegistry,
        EmptyContract _emptyContract,
        ProxyAdmin _proxyAdmin
    ) internal returns (IStrategyFactory) {
        vm.startBroadcast(deployer);

        // Create base strategy implementation and deploy a few strategies
        StrategyBase strategyImpl = new StrategyBase(
            _strategyManager,
            _pauserRegistry,
            EIGENLAYER_VERSION
        );

        IStrategyFactory strategyFactoryProxy = IStrategyFactory(
            address(new TransparentUpgradeableProxy(address(_emptyContract), address(_proxyAdmin), ""))
        );

        StrategyFactory strategyFactoryImpl = new StrategyFactory(
            _strategyManager,
            _pauserRegistry,
            EIGENLAYER_VERSION
        );

        // Strategy Factory, upgrade and initalized
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(strategyFactoryProxy))),
            address(strategyFactoryImpl),
            abi.encodeWithSelector(
                StrategyFactory.initialize.selector,
                deployer, // initialOwner
                0, // initial paused status
                IBeacon(new UpgradeableBeacon(address(strategyImpl)))
                // Create a proxy beacon for base strategy implementation
            )
        );

        _strategyManager.setStrategyWhitelister(address(strategyFactoryProxy));

        vm.stopBroadcast();

        return strategyFactoryProxy;
    }

    function deployERC20Minter(
        string memory name,
        string memory symbol,
        ProxyAdmin _proxyAdmin
    ) public returns (ERC20Minter) {
        vm.startBroadcast(deployer);

        ERC20Minter erc20proxy = ERC20Minter(
            address(
                new TransparentUpgradeableProxy(
                    address(new ERC20Minter()),
                    address(_proxyAdmin),
                    abi.encodeWithSelector(
                        ERC20Minter.initialize.selector,
                        name,
                        symbol
                    )
                )
            )
        );

        vm.stopBroadcast();
        return erc20proxy;
    }

    struct EigenlayerAddresses {
        IStrategy strategy;
        IStrategyManager strategyManager;
        IStrategyFactory strategyFactory;
        IPauserRegistry pauserRegistry;
        IDelegationManager delegationManager;
        IAllocationManager allocationManager;
        IRewardsCoordinator rewardsCoordinator;
        IERC20 tokenERC20;
    }

    function readSavedEigenlayerAddresses() public returns (EigenlayerAddresses memory) {

        chains[31337] = "localhost";
        chains[17000] = "holesky";
        chains[84532] = "basesepolia";
        chains[11155111] = "ethsepolia";
        // Eigenlayer contract addresses are only on EthSepolia and localhost, not L2

        string memory deploymentData = vm.readFile(
            string(abi.encodePacked(
                "script/",
                chains[block.chainid],
                "/eigenLayerContracts.config.json"
            ))
        );

        EigenlayerAddresses memory ea;
        ea.strategy = IStrategy(stdJson.readAddress(deploymentData, ".addresses.strategies.CCIPStrategy"));
        ea.strategyManager = IStrategyManager(stdJson.readAddress(deploymentData, ".addresses.StrategyManager"));
        ea.strategyFactory = IStrategyFactory(stdJson.readAddress(deploymentData, ".addresses.StrategyFactory"));
        ea.pauserRegistry = IPauserRegistry(stdJson.readAddress(deploymentData, ".addresses.PauserRegistry"));
        ea.delegationManager = IDelegationManager(stdJson.readAddress(deploymentData, ".addresses.DelegationManager"));
        ea.allocationManager = IAllocationManager(stdJson.readAddress(deploymentData, ".addresses.AllocationManager"));
        ea.rewardsCoordinator = IRewardsCoordinator(stdJson.readAddress(deploymentData, ".addresses.RewardsCoordinator"));
        ea.tokenERC20 = IERC20(stdJson.readAddress(deploymentData, ".addresses.TokenERC20"));

        require(address(ea.strategy) != address(0), "readSavedEigenlayerAddresses: _strategy missing");
        require(address(ea.strategyManager) != address(0), "readSavedEigenlayerAddresses: _strategyManager missing");
        require(address(ea.strategyFactory) != address(0), "readSavedEigenlayerAddresses: _strategyFactory missing");
        require(address(ea.pauserRegistry) != address(0), "readSavedEigenlayerAddresses: _pauserRegistry missing");
        require(address(ea.delegationManager) != address(0), "readSavedEigenlayerAddresses: _delegationManager missing");
        require(address(ea.allocationManager) != address(0), "readSavedEigenlayerAddresses: _allocationManager missing");
        require(address(ea.rewardsCoordinator) != address(0), "readSavedEigenlayerAddresses: _rewardsCoordinator missing");
        require(address(ea.tokenERC20) != address(0), "readSavedEigenlayerAddresses: _tokenERC20 missing");

        return ea;
    }

    function writeContractAddresses(
        address _strategy,
        address _strategyManager,
        address _strategyFactory,
        address _pauserRegistry,
        address _delegationManager,
        address _allocationManager,
        address _rewardsCoordinator,
        address _tokenERC20,
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
        vm.serializeAddress(keyAddresses, "AllocationManager", _allocationManager);
        vm.serializeAddress(keyAddresses, "TokenERC20", _tokenERC20);
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
        chains[84532] = "basesepolia";
        chains[11155111] = "ethsepolia";

        string memory finalOutputPath = string(abi.encodePacked(
            "script/",
            chains[block.chainid],
            "/eigenlayerContracts.config.json"
        ));
        vm.writeJson(finalJson, finalOutputPath);
    }

    function test_ignore() private {}
}