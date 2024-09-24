// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, stdJson} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {IETHPOSDeposit} from "@eigenlayer-contracts/interfaces/IETHPOSDeposit.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategyFactory} from "@eigenlayer-contracts/interfaces/IStrategyFactory.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "@eigenlayer-contracts/interfaces/IPauserRegistry.sol";
import {ISlasher} from "@eigenlayer-contracts/interfaces/ISlasher.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IEigenPodManager} from "@eigenlayer-contracts/interfaces/IEigenPodManager.sol";

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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";
import {EthSepolia} from "./Addresses.sol";

/// @dev This deploys mock Eigenlayer contracts from the `dev` branch for the purpose
/// of testing deposits, withdrawals, and delegation with custom ERC20 strategies only.
/// It does not deploy and configure EigenPod and Slashing features (can add later).
contract DeployMockEigenlayerContractsScript is Script {

    uint256 private deployerKey = vm.envUint("DEPLOYER_KEY");
    address public deployer = vm.addr(deployerKey);

    mapping(uint256 => string) public chains;

    IERC20 public tokenERC20;
    IStrategyManager public strategyManager;
    ISlasher public slasher;
    IEigenPodManager public eigenPodManager;
    IPauserRegistry public pauserRegistry;
    IRewardsCoordinator public rewardsCoordinator;
    IDelegationManager public delegationManager;
    ProxyAdmin public proxyAdmin;
    EmptyContract public emptyContract;

    // RewardsCoordinator Parameters. TBD what they should be for Treasure chain
    uint32 public CALCULATION_INTERVAL_SECONDS = 604800; // 7 days
    uint32 public MAX_REWARDS_DURATION = 7257600; // 84 days
    uint32 public MAX_RETROACTIVE_LENGTH = 0; // 0 days // must be zero or reverts on anvil localhost
    uint32 public MAX_FUTURE_LENGTH = 2419200; // 28 days
    uint32 public GENESIS_REWARDS_TIMESTAMP = 0;

    uint256 public USER_DEPOSIT_LIMIT = 100_000 ether;  // uint256 _maxPerDeposit,
    uint256 public TOTAL_DEPOSIT_LIMIT = 10_000_000 ether; // uint256 _maxTotalDeposits,

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
        proxyAdmin = deployProxyAdmin();
        vm.startBroadcast(deployer);
        emptyContract = new EmptyContract();
        vm.stopBroadcast();

        (
            strategyManager,
            pauserRegistry,
            rewardsCoordinator,
            delegationManager
        ) = _deployEigenlayerCoreContracts(proxyAdmin);

        if (block.chainid != 11155111) {
            // can mint in localhost tests
            tokenERC20 = IERC20(address(deployERC20Minter("Mock MAGIC", "MMAGIC", proxyAdmin)));
        } else {
            // can't mint, you need to transfer CCIP-BnM tokens to receiver contract
            tokenERC20 = IERC20(address(IERC20_CCIPBnM(EthSepolia.BridgeToken)));
        }

        (StrategyFactory strategyFactory, UpgradeableBeacon strategyBeacon) = _deployStrategyFactory(
            StrategyManager(address(strategyManager)),
            pauserRegistry,
            emptyContract,
            proxyAdmin
        );

        vm.startBroadcast(deployer);
        IStrategy strategy = strategyFactory.deployNewStrategy(tokenERC20);

        // setStrategyWithdrawalDelayBlocks
        IStrategy[] memory strategies = new IStrategy[](1);
        strategies[0] = strategy;

        uint256[] memory withdrawalDelayBlocks = new uint256[](1);
        withdrawalDelayBlocks[0] = 1;

        DelegationManager(address(delegationManager)).setStrategyWithdrawalDelayBlocks(strategies, withdrawalDelayBlocks);

        vm.stopBroadcast();

        if (saveDeployedContracts) {
            // only when deploying
            writeContractAddresses(
                address(strategy),
                address(strategyManager),
                address(strategyFactory),
                address(pauserRegistry),
                address(delegationManager),
                address(rewardsCoordinator),
                address(strategyBeacon),
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
        IRewardsCoordinator,
        IDelegationManager
    ) {

        vm.startBroadcast(deployer);

        address[] memory pausers = new address[](1);
        pausers[0] = deployer;
        PauserRegistry _pauserRegistry = new PauserRegistry(pausers, deployer);

        // deploy first to get address for delegationManager
        strategyManager = StrategyManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(_proxyAdmin), ""))
        );
        vm.stopBroadcast();

        delegationManager = IDelegationManager(address(
            _deployDelegationManager(
                strategyManager,
                slasher,
                eigenPodManager,
                _pauserRegistry,
                _proxyAdmin
            )
        ));

        vm.startBroadcast(deployer);
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
        vm.stopBroadcast();

        rewardsCoordinator = _deployRewardsCoordinator(
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

    function _deployRewardsCoordinator(
        IStrategyManager _strategyManager,
        IDelegationManager _delegationManager,
        IPauserRegistry _pauserRegistry
    ) internal returns (RewardsCoordinator) {
        vm.startBroadcast(deployer);
        // Eigenlayer disableInitialisers so they must be called via upgradeable proxy
        RewardsCoordinator _rewardsCoordinator = new RewardsCoordinator(
            _delegationManager,
            _strategyManager,
            CALCULATION_INTERVAL_SECONDS ,
            MAX_REWARDS_DURATION,
            MAX_RETROACTIVE_LENGTH ,
            MAX_FUTURE_LENGTH,
            GENESIS_REWARDS_TIMESTAMP
        );

        _rewardsCoordinator = RewardsCoordinator(
            address(
                new TransparentUpgradeableProxy(
                    address(_rewardsCoordinator),
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
        return _rewardsCoordinator;
    }

    function _deployDelegationManager(
        IStrategyManager _strategyManager,
        ISlasher _slasher,
        IEigenPodManager _eigenPodManager,
        IPauserRegistry _pauserRegistry,
        ProxyAdmin _proxyAdmin
    ) internal returns (DelegationManager) {
        vm.startBroadcast(deployer);

        // deploy first to get address for delegationManager
        DelegationManager delegationManagerProxy = DelegationManager(
            address(new TransparentUpgradeableProxy(address(emptyContract), address(_proxyAdmin), ""))
        );

        _eigenPodManager = new EigenPodManager(
            IETHPOSDeposit(vm.addr(0xee01)),
            IBeacon(vm.addr(0xee02)),
            _strategyManager,
            _slasher,
            delegationManagerProxy
        );

        // Eigenlayer disableInitialisers so they must be called via upgradeable proxy
        DelegationManager delegationManagerImpl = new DelegationManager(
            _strategyManager,
            _slasher,
            _eigenPodManager
        );

        proxyAdmin.upgradeAndCall(
            TransparentUpgradeableProxy(payable(address(delegationManagerProxy))),
            address(delegationManagerImpl),
            abi.encodeWithSelector(
                DelegationManager.initialize.selector,
                deployer,
                _pauserRegistry,
                0, // initialPausedStatus
                4, // _minWithdrawalDelayBlocks: 4x15 seconds = 1 min
                new IStrategy[](0), // _strategies
                new uint256[](0) // _withdrawalDelayBlocks
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
    ) internal returns (StrategyFactory, UpgradeableBeacon) {
        vm.startBroadcast(deployer);

        // Create base strategy implementation and deploy a few strategies
        StrategyBase strategyImpl = new StrategyBase(_strategyManager);

        // Create a proxy beacon for base strategy implementation
        UpgradeableBeacon strategyBeacon = new UpgradeableBeacon(address(strategyImpl));

        StrategyFactory strategyFactory = StrategyFactory(
            address(new TransparentUpgradeableProxy(address(_emptyContract), address(_proxyAdmin), ""))
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

        return (strategyFactory, strategyBeacon);
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

    function deployStrategyTVLLimits(
        IStrategyManager _strategyManager,
        IPauserRegistry _pauserRegistry,
        IERC20 _tokenERC20,
        ProxyAdmin _proxyAdmin
    ) public returns (StrategyBaseTVLLimits) {
        vm.startBroadcast(deployer);

        require(address(_tokenERC20) != address(0), "tokenERC20 missing");
        require(address(_strategyManager) != address(0), "strategyManager missing");
        require(address(_pauserRegistry) != address(0), "pauserRegistry missing");

        StrategyBaseTVLLimits strategyImpl = new StrategyBaseTVLLimits(_strategyManager);

        StrategyBaseTVLLimits strategyProxy = StrategyBaseTVLLimits(
            address(
                new TransparentUpgradeableProxy(
                    address(strategyImpl),
                    address(_proxyAdmin),
                    abi.encodeWithSelector(
                        StrategyBaseTVLLimits.initialize.selector,
                        USER_DEPOSIT_LIMIT,  // uint256 _maxPerDeposit,
                        TOTAL_DEPOSIT_LIMIT, // uint256 _maxTotalDeposits,
                        _tokenERC20,          // IERC20 _underlyingToken,
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
        IRewardsCoordinator,
        IERC20
    ) {

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

        address _strategy = stdJson.readAddress(deploymentData, ".addresses.strategies.CCIPStrategy");
        address _strategyManager = stdJson.readAddress(deploymentData, ".addresses.StrategyManager");
        address _strategyFactory = stdJson.readAddress(deploymentData, ".addresses.StrategyFactory");
        address _pauserRegistry = stdJson.readAddress(deploymentData, ".addresses.PauserRegistry");
        address _delegationManager = stdJson.readAddress(deploymentData, ".addresses.DelegationManager");
        address _rewardsCoordinator = stdJson.readAddress(deploymentData, ".addresses.RewardsCoordinator");
        address _tokenERC20 = stdJson.readAddress(deploymentData, ".addresses.TokenERC20");

        require(_strategy != address(0), "readSavedEigenlayerAddresses: _strategy missing");
        require(_strategyManager != address(0), "readSavedEigenlayerAddresses: _strategyManager missing");
        require(_strategyFactory != address(0), "readSavedEigenlayerAddresses: _strategyFactory missing");
        require(_delegationManager != address(0), "readSavedEigenlayerAddresses: _delegationManager missing");
        require(_rewardsCoordinator != address(0), "readSavedEigenlayerAddresses: _rewardsCoordinator missing");
        require(_pauserRegistry != address(0), "readSavedEigenlayerAddresses: _pauserRegistry missing");
        require(_tokenERC20 != address(0), "readSavedEigenlayerAddresses: _tokenERC20 missing");

        return (
            IStrategy(_strategy),
            IStrategyManager(_strategyManager),
            IStrategyFactory(_strategyFactory),
            IPauserRegistry(_pauserRegistry),
            IDelegationManager(_delegationManager),
            IRewardsCoordinator(_rewardsCoordinator),
            IERC20(_tokenERC20)
        );
    }

    function writeContractAddresses(
        address _strategy,
        address _strategyManager,
        address _strategyFactory,
        address _pauserRegistry,
        address _delegationManager,
        address _rewardsCoordinator,
        address _strategyBeacon,
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
        vm.serializeAddress(keyAddresses, "StrategyBeacon", _strategyBeacon);
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