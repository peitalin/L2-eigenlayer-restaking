// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {ScriptUtils} from "./ScriptUtils.sol";
import {FileReader} from "./FileReader.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";


contract MintEigenAgentScript is Script, ScriptUtils {

    uint256 public deployerKey;
    address public deployer;

    uint256 public aliceKey;
    address public alice;

    FileReader public fileReader; // keep outside vm.startBroadcast() to avoid deploying
    IAgentFactory public agentFactory;
    IEigenAgent6551 public eigenAgent;

    function run() public {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        aliceKey = uint256(5555);
        alice = vm.addr(aliceKey);

        fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        agentFactory = fileReader.readAgentFactory();

        vm.createSelectFork("ethsepolia");
        vm.startBroadcast(deployerKey);

        eigenAgent = agentFactory.getEigenAgent(deployer);
        if (address(eigenAgent) == address(0)) {
            eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);
        }
        console.log("eigenAgent:", address(eigenAgent));

        vm.stopBroadcast();
    }
}
