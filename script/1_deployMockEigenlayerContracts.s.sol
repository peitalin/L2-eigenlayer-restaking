// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, stdJson} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-v47-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-v5-contracts/proxy/transparent/ProxyAdmin.sol";

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
import {IERC20} from "@openzeppelin-v47-contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";
import {EthHolesky} from "./Addresses.sol";

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

        // Eigenlayer Holesky Contracts
        (
            IStrategyManager strategyManager,
            IStrategyFactory strategyFactory,
            IPauserRegistry pauserRegistry,
            IDelegationManager delegationManager,
            IRewardsCoordinator rewardsCoordinator
        ) = readSavedEigenlayerAddresses();

        // localhost chainid
        if (block.chainid == 31337) {
            // can mint in localhost tests
            tokenERC20 = IERC20(address(deployERC20Minter("Mock MAGIC", "MMAGIC", proxyAdmin)));
        } else {
            // can't mint, you need to transfer CCIP-BnM tokens to receiver contract
            tokenERC20 = IERC20(address(IERC20_CCIPBnM(EthHolesky.BridgeToken)));
            // tokenERC20 = IERC20(address(deployERC20Minter("Mock MAGIC", "MMAGIC", proxyAdmin)));
        }

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

    function deployProxyAdmin() public returns (ProxyAdmin) {
        vm.startBroadcast(deployer);
        ProxyAdmin _proxyAdmin = new ProxyAdmin(deployer);
        vm.stopBroadcast();
        return _proxyAdmin;
    }

    // function _deployRewardsCoordinator(
    //     IStrategyManager _strategyManager,
    //     IDelegationManager _delegationManager,
    //     IPauserRegistry _pauserRegistry
    // ) internal returns (RewardsCoordinator) {
    //     vm.startBroadcast(deployer);
    //     // Eigenlayer disableInitialisers so they must be called via upgradeable proxy
    //     RewardsCoordinator _rewardsCoordinator = new RewardsCoordinator(
    //         _delegationManager,
    //         _strategyManager,
    //         CALCULATION_INTERVAL_SECONDS ,
    //         MAX_REWARDS_DURATION,
    //         MAX_RETROACTIVE_LENGTH ,
    //         MAX_FUTURE_LENGTH,
    //         GENESIS_REWARDS_TIMESTAMP
    //     );
    //     _rewardsCoordinator = RewardsCoordinator(
    //         address(
    //             new TransparentUpgradeableProxy(
    //                 address(_rewardsCoordinator),
    //                 address(proxyAdmin),
    //                 abi.encodeWithSelector(
    //                     RewardsCoordinator.initialize.selector,
    //                     deployer, // initialOwner
    //                     _pauserRegistry,
    //                     0, // initialPausedStatus
    //                     deployer, // rewardsUpdater
    //                     0, // activation delay
    //                     0 // global commission Bips
    //                 )
    //             )
    //         )
    //     );
    //     vm.stopBroadcast();
    //     return _rewardsCoordinator;
    // }

    function deployERC20Minter(
        string memory name,
        string memory symbol,
        ProxyAdmin _proxyAdmin
    ) public returns (ERC20Minter) {
        vm.startBroadcast(deployer);
        ERC20Minter erc20proxy = ERC20Minter(address(
            new TransparentUpgradeableProxy(
                address(new ERC20Minter()),
                address(_proxyAdmin),
                abi.encodeWithSelector(
                    ERC20Minter.initialize.selector,
                    name,
                    symbol
                )
            )
        ));
        vm.stopBroadcast();
        return erc20proxy;
    }

    function readSavedEigenlayerStrategy() public returns (
        IStrategy,
        IERC20,
        ProxyAdmin
    ) {

        chains[31337] = "localhost";
        chains[17000] = "holesky";
        chains[84532] = "basesepolia";

        string memory deploymentData = vm.readFile(
            string(abi.encodePacked(
                "script/",
                chains[block.chainid],
                "/eigenLayerContracts.config.json"
            ))
        );

        address _strategy = stdJson.readAddress(deploymentData, ".addresses.strategies.CCIPStrategy");
        address _tokenERC20 = stdJson.readAddress(deploymentData, ".addresses.TokenERC20");
        address _proxyAdmin = stdJson.readAddress(deploymentData, ".addresses.ProxyAdmin");

        require(_strategy != address(0), "readSavedEigenlayerAddresses: _strategy missing");
        require(_tokenERC20 != address(0), "readSavedEigenlayerAddresses: _tokenERC20 missing");
        require(_proxyAdmin != address(0), "readSavedEigenlayerAddresses: _proxyAdmin missing");

        return (
            IStrategy(_strategy),
            IERC20(_tokenERC20),
            ProxyAdmin(_proxyAdmin)
        );
    }

    function readSavedEigenlayerAddresses() public returns (
        IStrategyManager,
        IStrategyFactory,
        IPauserRegistry,
        IDelegationManager,
        IRewardsCoordinator
    ) {

        chains[31337] = "localhost";
        chains[17000] = "holesky";
        chains[84532] = "basesepolia";

        string memory deploymentData = vm.readFile(
            string(abi.encodePacked(
                "script/",
                chains[block.chainid],
                "/eigenLayerContracts.config.json"
            ))
        );

        address _strategyManager = stdJson.readAddress(deploymentData, ".addresses.StrategyManager");
        address _strategyFactory = stdJson.readAddress(deploymentData, ".addresses.StrategyFactory");
        address _pauserRegistry = stdJson.readAddress(deploymentData, ".addresses.PauserRegistry");
        address _delegationManager = stdJson.readAddress(deploymentData, ".addresses.DelegationManager");
        address _rewardsCoordinator = stdJson.readAddress(deploymentData, ".addresses.RewardsCoordinator");

        require(_strategyManager != address(0), "readSavedEigenlayerAddresses: _strategyManager missing");
        require(_strategyFactory != address(0), "readSavedEigenlayerAddresses: _strategyFactory missing");
        require(_delegationManager != address(0), "readSavedEigenlayerAddresses: _delegationManager missing");
        require(_rewardsCoordinator != address(0), "readSavedEigenlayerAddresses: _rewardsCoordinator missing");
        require(_pauserRegistry != address(0), "readSavedEigenlayerAddresses: _pauserRegistry missing");

        return (
            IStrategyManager(_strategyManager),
            IStrategyFactory(_strategyFactory),
            IPauserRegistry(_pauserRegistry),
            IDelegationManager(_delegationManager),
            IRewardsCoordinator(_rewardsCoordinator)
        );
    }

    function writeContractAddresses(
        address _strategy,
        address _strategyManager,
        address _strategyFactory,
        address _pauserRegistry,
        address _delegationManager,
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

        string memory finalOutputPath = string(abi.encodePacked(
            "script/",
            chains[block.chainid],
            "/eigenlayerContracts.config.json"
        ));
        vm.writeJson(finalJson, finalOutputPath);
    }

    function test_ignore() private {}
}