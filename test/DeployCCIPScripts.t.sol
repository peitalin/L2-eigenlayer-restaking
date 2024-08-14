// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";

import {DeployOnArbScript} from "../script/2_deployOnArb.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";
import {WhitelistCCIPContractsScript} from "../script/4_whitelistCCIPContracts.s.sol";
import {DepositWithSignatureFromArbToEthScript} from "../script/5_depositWithSignatureFromArbToEth.s.sol";
import {DepositFromArbToEthScript} from "../script/x4_depositFromArbToEth.s.sol";
import {QueueWithdrawalWithSignatureScript} from "../script/6_queueWithdrawalWithSignature.s.sol";
import {CompleteWithdrawalWithSignatureScript} from "../script/7_completeWithdrawalWithSignature.s.sol";


contract DeployCCIPScriptsTest is Test {

    // deploy scripts
    DeployOnArbScript public deployOnArbScript;
    DeployOnEthScript public deployOnEthScript;
    DepositWithSignatureFromArbToEthScript public depositWithSignatureFromArbToEthScript;
    DepositFromArbToEthScript public depositFromArbToEthScript;
    QueueWithdrawalWithSignatureScript public queueWithdrawalWithSignatureScript;
    CompleteWithdrawalWithSignatureScript public completeWithdrawalWithSignatureScript;
    WhitelistCCIPContractsScript public whitelistCCIPContractsScript;

    uint256 public deployerKey;
    address public deployer;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deployOnArbScript = new DeployOnArbScript();
        deployOnEthScript = new DeployOnEthScript();
        whitelistCCIPContractsScript = new WhitelistCCIPContractsScript();
        depositFromArbToEthScript = new DepositFromArbToEthScript();
        depositWithSignatureFromArbToEthScript = new DepositWithSignatureFromArbToEthScript();
        queueWithdrawalWithSignatureScript = new QueueWithdrawalWithSignatureScript();
        completeWithdrawalWithSignatureScript = new CompleteWithdrawalWithSignatureScript();
    }

    function test_step2_DeployOnArbScript() public {
        deployOnArbScript.run();
    }

    function test_step3_DeployOnEthScript() public {
        deployOnEthScript.run();
    }

    function test_step4_WhitelistCCIPContractsScript() public {
        whitelistCCIPContractsScript.run();
    }

    function test_stepx4_DepositFromArbToEthScript() public {
        vm.chainId(421614); // mock Arbitrum Sepolia
        depositFromArbToEthScript.run();
    }

    function test_step5_DepositWithSignatureFromArbToEthScript() public {
        vm.chainId(421614); // mock Arbitrum Sepolia
        depositWithSignatureFromArbToEthScript.run();
    }

    function test_step6_QueueWithdrawalWithSignatureScript() public {
        vm.chainId(421614); // mock Arbitrum Sepolia
        queueWithdrawalWithSignatureScript.run();
    }

    function test_step7_CompleteWithdrawalWithSignatureScript() public {
        vm.chainId(421614); // mock Arbitrum Sepolia
        completeWithdrawalWithSignatureScript.run();
    }
}
