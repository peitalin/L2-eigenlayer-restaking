// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {ScriptUtils} from "./ScriptUtils.sol";
import {FileReader} from "./FileReader.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";


contract MintEigenAgentScript is Script, ScriptUtils, FileReader {

    uint256 public deployerKey;
    address public deployer;

    uint256 public aliceKey;
    address public alice;

    IAgentFactory public agentFactory;
    IEigenAgent6551 public eigenAgent;

    function run() public {
        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        aliceKey = deployerKey;
        alice = deployer;
        return _run();
    }

    function mockrun(uint256 _mockKey) public {
        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        aliceKey = _mockKey;
        alice = vm.addr(aliceKey);
        return _run();
    }

    function _run() public {

        vm.createSelectFork("ethsepolia");

        agentFactory = readAgentFactory();

        vm.createSelectFork("ethsepolia");
        vm.startBroadcast(deployerKey);

        eigenAgent = agentFactory.getEigenAgent(alice);
        if (address(eigenAgent) == address(0)) {
            eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(alice);
        }
        console.log("eigenAgent:", address(eigenAgent));

        vm.stopBroadcast();
    }
}
