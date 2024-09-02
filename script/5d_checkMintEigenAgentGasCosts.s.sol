// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script} from "forge-std/Script.sol";
import {ScriptUtils} from "./ScriptUtils.sol";
import {FileReader} from "./FileReader.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";


contract CheckMintEigenAgentGasCostsScript is Script, ScriptUtils, FileReader {

    uint256 public deployerKey;
    address public deployer;

    function run() public {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        IAgentFactory agentFactory = readAgentFactory();

        // Just for testing gas costs
        // forge test --match-test test_step5c_CheckMintEigenAgentGasCosts -vvvv --gas-report

        vm.createSelectFork("ethsepolia");
        vm.startBroadcast(deployer);

        uint256 bobKey = uint256(8888);
        address bob = vm.addr(bobKey);
        IEigenAgent6551 eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(bob);

        vm.stopBroadcast();
    }
}
