// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseScript} from "./BaseScript.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";


contract CheckMintEigenAgentGasCostsScript is BaseScript {

    uint256 deployerKey;
    address deployer;

    function run() public {
        return _run(false);
    }

    function mockrun() public {
        return _run(true);
    }

    function _run(bool isTest) private {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        readContractsAndSetupEnvironment(isTest, deployer);

        IAgentFactory agentFactory = readAgentFactory();

        // Just for testing gas costs
        // forge test --match-test test_step5d_CheckMintEigenAgentGasCosts -vvvv --gas-report

        vm.selectFork(ethForkId);
        vm.startBroadcast(deployer);

        uint256 bobKey = uint256(8888);
        address bob = vm.addr(bobKey);
        IEigenAgent6551 eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(bob);
        vm.assertNotEq(address(eigenAgent), address(0));

        vm.stopBroadcast();
    }
}
