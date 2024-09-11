// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {BaseScript} from "./BaseScript.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";


contract MintEigenAgentScript is BaseScript {

    uint256 public aliceKey;
    address public alice;

    IEigenAgent6551 public eigenAgent;

    function run() public {
        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        aliceKey = deployerKey;
        alice = deployer;
        return _run(false);
    }

    function mockrun(uint256 _mockKey) public {
        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        aliceKey = _mockKey;
        alice = vm.addr(aliceKey);
        return _run(true);
    }

    function _run(bool isTest) public {

        readContractsAndSetupEnvironment(isTest);

        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        eigenAgent = agentFactory.getEigenAgent(alice);
        if (address(eigenAgent) == address(0)) {
            eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(alice);
        }

        vm.stopBroadcast();
    }
}
