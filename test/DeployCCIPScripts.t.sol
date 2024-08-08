// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {DeployOnArbScript} from "../script/2_deployOnArb.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";
import {DepositWithSignatureFromArbToEthScript} from "../script/5_depositWithSignatureFromArbToEth.s.sol";
import {DepositFromArbToEthScript} from "../script/x4_depositFromArbToEth.s.sol";


contract DeployCCIPScriptsTest is Test {

    // deploy scripts
    DeployOnArbScript public deployOnArbScript;
    DeployOnEthScript public deployOnEthScript;
    DepositWithSignatureFromArbToEthScript public depositWithSignatureFromArbToEthScript;
    DepositFromArbToEthScript public depositFromArbToEthScript;

    uint256 public deployerKey;
    address public deployer;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deployOnArbScript = new DeployOnArbScript();
        deployOnEthScript = new DeployOnEthScript();
        depositFromArbToEthScript = new DepositFromArbToEthScript();
        depositWithSignatureFromArbToEthScript = new DepositWithSignatureFromArbToEthScript();
    }

    function test_DeployOnArbScript() public {
        deployOnArbScript.run();
    }

    function test_DeployOnEthScript() public {
        deployOnEthScript.run();
    }

    function test_DepositFromArbToEthScript() public {
        vm.chainId(421614); // mock Arbitrum Sepolia
        depositFromArbToEthScript.run();
    }

    function test_DepositWithSignatureFromArbToEthScript() public {
        vm.chainId(421614); // mock Arbitrum Sepolia
        depositWithSignatureFromArbToEthScript.run();
    }

}
