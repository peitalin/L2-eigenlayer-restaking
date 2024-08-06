// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {DeployOnArbScript} from "../script/2_deployOnArb.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";


contract DeployCCIPScriptsTest is Test {

    // deploy scripts
    DeployOnArbScript public deployOnArbScript;
    DeployOnEthScript public deployOnEthScript;

    uint256 public deployerKey;
    address public deployer;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deployOnArbScript = new DeployOnArbScript();
        deployOnEthScript = new DeployOnEthScript();
    }

    function test_DeployOnArbScript() public {
        deployOnArbScript.run();
    }

    function test_DeployOnEthScript() public {
        deployOnEthScript.run();
    }

}
