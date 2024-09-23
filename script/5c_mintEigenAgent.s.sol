// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseScript} from "./BaseScript.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";


contract MintEigenAgentScript is BaseScript {

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);
    uint256 aliceKey;
    address alice;

    IEigenAgent6551 public eigenAgent;

    function run() public {
        aliceKey = deployerKey;
        alice = deployer;
        return _run(false);
    }

    function mockrun(uint256 _mockKey) public {
        aliceKey = _mockKey;
        alice = vm.addr(aliceKey);
        return _run(true);
    }

    function _run(bool isTest) public {

        readContractsAndSetupEnvironment(isTest, deployer);

        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        eigenAgent = agentFactory.getEigenAgent(alice);
        if (address(eigenAgent) == address(0)) {
            eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(alice);
        }

        vm.stopBroadcast();
    }

    function test_ignore_mintEigenAgent() private {}
}

