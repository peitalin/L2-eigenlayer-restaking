// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, stdJson} from "forge-std/Script.sol";

import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategyFactory} from "@eigenlayer-contracts/interfaces/IStrategyFactory.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "@eigenlayer-contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IAllocationManager} from "@eigenlayer-contracts/interfaces/IAllocationManager.sol";
import {IERC20} from "@openzeppelin-v4-contracts/token/ERC20/IERC20.sol";
import {EthSepolia} from "./Addresses.sol";


contract SetupRealEigenlayerContractsScript is Script {

    uint256 private deployerKey = vm.envUint("DEPLOYER_KEY");
    address public deployer = vm.addr(deployerKey);
    mapping(uint256 => string) public chains;

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

    function run() public {

        if (block.chainid != 1 && block.chainid != 11155111 && block.chainid != 17000) {
            revert("must deploy on Eth Mainnet, Sepolia, or Holesky");
        }

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        EigenlayerAddresses memory ea = readRealEigenlayerAddresses();

        IERC20 tokenERC20 = IERC20(EthSepolia.BridgeToken);

        vm.prank(deployer);
        IStrategy strategy = ea.strategyFactory.deployNewStrategy(tokenERC20);

        saveEigenlayerStrategy(
            ea,
            address(strategy),
            address(tokenERC20)
        );
    }

    function readRealEigenlayerAddresses() public returns (EigenlayerAddresses memory) {

        chains[17000] = "holesky";
        chains[11155111] = "ethsepolia";
        chains[1] = "mainnet";

        string memory deploymentData = vm.readFile(
            string(abi.encodePacked(
                "script/",
                chains[block.chainid],
                "/realEigenLayerContracts.config.json"
            ))
        );

        EigenlayerAddresses memory ea;
        // ea.strategy = address(0);
        ea.strategyManager = IStrategyManager(stdJson.readAddress(deploymentData, ".addresses.StrategyManager"));
        ea.strategyFactory = IStrategyFactory(stdJson.readAddress(deploymentData, ".addresses.StrategyFactory"));
        ea.pauserRegistry = IPauserRegistry(stdJson.readAddress(deploymentData, ".addresses.PauserRegistry"));
        ea.delegationManager = IDelegationManager(stdJson.readAddress(deploymentData, ".addresses.DelegationManager"));
        ea.allocationManager = IAllocationManager(stdJson.readAddress(deploymentData, ".addresses.AllocationManager"));
        ea.rewardsCoordinator = IRewardsCoordinator(stdJson.readAddress(deploymentData, ".addresses.RewardsCoordinator"));
        // ea.tokenERC20 = address(0);

        // require(address(ea.strategy) != address(0), "readSavedEigenlayerAddresses: _strategy missing");
        require(address(ea.strategyManager) != address(0), "readSavedEigenlayerAddresses: _strategyManager missing");
        require(address(ea.strategyFactory) != address(0), "readSavedEigenlayerAddresses: _strategyFactory missing");
        require(address(ea.pauserRegistry) != address(0), "readSavedEigenlayerAddresses: _pauserRegistry missing");
        require(address(ea.delegationManager) != address(0), "readSavedEigenlayerAddresses: _delegationManager missing");
        require(address(ea.allocationManager) != address(0), "readSavedEigenlayerAddresses: _allocationManager missing");
        require(address(ea.rewardsCoordinator) != address(0), "readSavedEigenlayerAddresses: _rewardsCoordinator missing");
        // require(address(ea.tokenERC20) != address(0), "readSavedEigenlayerAddresses: _tokenERC20 missing");

        return ea;
    }

    function saveEigenlayerStrategy(
        EigenlayerAddresses memory ea,
        address _strategy,
        address _tokenERC20
    ) public {

        /////////////////////////////////////////////////
        // { "addresses": <addresses_output>}
        /////////////////////////////////////////////////
        string memory keyAddresses = "addresses";
        vm.serializeAddress(keyAddresses, "StrategyManager", address(ea.strategyManager));
        vm.serializeAddress(keyAddresses, "StrategyFactory", address(ea.strategyFactory));
        vm.serializeAddress(keyAddresses, "PauserRegistry", address(ea.pauserRegistry));
        vm.serializeAddress(keyAddresses, "RewardsCoordinator", address(ea.rewardsCoordinator));
        vm.serializeAddress(keyAddresses, "DelegationManager", address(ea.delegationManager));
        vm.serializeAddress(keyAddresses, "AllocationManager", address(ea.allocationManager));
        vm.serializeAddress(keyAddresses, "TokenERC20", address(ea.tokenERC20));

        /////////////////////////////////////////////////
        // { "addresses": { "strategies": <strategies_output>}}
        /////////////////////////////////////////////////
        string memory keyStrategies = "strategies";
        string memory strategies_output = vm.serializeAddress(
            keyStrategies,
            "Strategy",
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

        chains[17000] = "holesky";
        chains[11155111] = "ethsepolia";
        chains[1] = "mainnet";

        if (block.chainid != 11155111 && block.chainid != 17000 && block.chainid != 1) {
            revert("Must run on Eth Mainnet, Sepolia, or Holesky");
        }

        string memory finalOutputPath = string(abi.encodePacked(
            "script/",
            chains[block.chainid],
            "/realEigenlayerContracts.config.json"
        ));
        vm.writeJson(finalJson, finalOutputPath);
    }

    function test_ignore() private {}
}