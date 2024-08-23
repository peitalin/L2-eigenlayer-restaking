// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";

import {DeployOnL2Script} from "../script/2_deployOnL2.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";
import {WhitelistCCIPContractsScript} from "../script/4_whitelistCCIPContracts.s.sol";
import {DepositFromArbToEthScript} from "../script/x4_depositFromArbToEth.s.sol";
import {DepositWithSignatureScript} from "../script/5_depositWithSignature.s.sol";
import {DelegateToScript} from "../script/6_delegateTo.s.sol";
import {QueueWithdrawalWithSignatureScript} from "../script/7_queueWithdrawalWithSignature.s.sol";
import {CompleteWithdrawalScript} from "../script/8_completeWithdrawal.s.sol";
import {ScriptUtils} from "../script/ScriptUtils.sol";


contract DeployCCIPScriptsTest is Test, ScriptUtils {

    // deploy scripts
    DeployOnL2Script public deployOnL2Script;
    DeployOnEthScript public deployOnEthScript;
    WhitelistCCIPContractsScript public whitelistCCIPContractsScript;

    DepositFromArbToEthScript public depositFromArbToEthScript;
    DepositWithSignatureScript public depositWithSignatureScript;

    DelegateToScript public delegateToScript;

    QueueWithdrawalWithSignatureScript public queueWithdrawalWithSignatureScript;
    CompleteWithdrawalScript public completeWithdrawalScript;

    uint256 public deployerKey;
    address public deployer;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployer);

        deployOnL2Script = new DeployOnL2Script();
        deployOnEthScript = new DeployOnEthScript();
        whitelistCCIPContractsScript = new WhitelistCCIPContractsScript();

        depositFromArbToEthScript = new DepositFromArbToEthScript();
        depositWithSignatureScript = new DepositWithSignatureScript();

        delegateToScript = new DelegateToScript();

        queueWithdrawalWithSignatureScript = new QueueWithdrawalWithSignatureScript();
        completeWithdrawalScript = new CompleteWithdrawalScript();

        vm.stopBroadcast();

        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        vm.deal(deployer, 1 ether);
    }

    function test_step2_DeployOnL2Script() public {
        deployOnL2Script.run();
    }

    function test_step3_DeployOnEthScript() public {
        deployOnEthScript.run();
    }

    function test_step4_WhitelistCCIPContractsScript() public {
        whitelistCCIPContractsScript.run();
    }

    function test_stepx4_DepositScript() public {
        depositFromArbToEthScript.run();
    }

    function test_step5_DepositWithSignatureScript() public {
        depositWithSignatureScript.run();
    }

    function test_step6_DelegateToScript() public {
        delegateToScript.run();
    }

    // writes new withdrawalRoots
    function test_step7_QueueWithdrawalWithSignatureScript() public {
        queueWithdrawalWithSignatureScript.run();
    }

    function test_step8_CompleteWithdrawalScript() public {
        completeWithdrawalScript.run();
    }
}

