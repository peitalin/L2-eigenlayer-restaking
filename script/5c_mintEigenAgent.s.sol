// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {BaseScript} from "./BaseScript.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";


contract MintEigenAgentScript is BaseScript {

    uint256 deployerKey;
    address deployer;
    uint256 aliceKey;
    address alice;

    IEigenAgent6551 public eigenAgent;

    function run() public {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        aliceKey = deployerKey;
        alice = deployer;
        readContractsAndSetupEnvironment(false, deployer);

        return _run();
    }

    function mockrun(uint256 _mockKey) public {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        aliceKey = _mockKey;
        alice = vm.addr(aliceKey);
        readContractsAndSetupEnvironment(true, deployer);

        return _run();
    }

    function _run() public {


        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        eigenAgent = agentFactory.getEigenAgent(alice);
        if (address(eigenAgent) == address(0)) {
            eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(alice);
        }

        vm.stopBroadcast();
    }
}
