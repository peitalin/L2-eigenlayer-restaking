// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";

import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";
import {UpgradeSenderOnL2Script} from "../script/2b_upgradeSenderOnL2.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {UpgradeReceiverOnL1Script} from "../script/3b_upgradeReceiverOnL1.s.sol";
import {WhitelistCCIPContractsScript} from "../script/4_whitelistCCIPContracts.s.sol";
import {DepositWithSignatureScript} from "../script/5_depositWithSignature.s.sol";
import {MintEigenAgentScript} from "../script/5b_mintEigenAgent.s.sol";
import {DelegateToScript} from "../script/6_delegateTo.s.sol";
import {QueueWithdrawalWithSignatureScript} from "../script/7_queueWithdrawalWithSignature.s.sol";
import {CompleteWithdrawalScript} from "../script/8_completeWithdrawal.s.sol";
import {TestDeployVerifyScript} from "../script/x_testDeployVerify.s.sol";
import {ScriptUtils} from "../script/ScriptUtils.sol";


contract DeployScriptsTests is Test, ScriptUtils {

    // deploy scripts
    DeploySenderOnL2Script public deploySenderOnL2Script;
    UpgradeSenderOnL2Script public upgradeSenderOnL2Script;

    DeployReceiverOnL1Script public deployReceiverOnL1Script;
    UpgradeReceiverOnL1Script public upgradeReceiverOnL1Script;

    WhitelistCCIPContractsScript public whitelistCCIPContractsScript;

    DepositWithSignatureScript public depositWithSignatureScript;
    MintEigenAgentScript public mintEigenAgentScript;

    DelegateToScript public delegateToScript;

    QueueWithdrawalWithSignatureScript public queueWithdrawalWithSignatureScript;
    CompleteWithdrawalScript public completeWithdrawalScript;

    TestDeployVerifyScript public testDeployVerifyScript;

    uint256 public deployerKey;
    address public deployer;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deploySenderOnL2Script = new DeploySenderOnL2Script();
        upgradeSenderOnL2Script = new UpgradeSenderOnL2Script();

        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
        upgradeReceiverOnL1Script = new UpgradeReceiverOnL1Script();

        whitelistCCIPContractsScript = new WhitelistCCIPContractsScript();

        depositWithSignatureScript = new DepositWithSignatureScript();
        mintEigenAgentScript = new MintEigenAgentScript();

        delegateToScript = new DelegateToScript();

        queueWithdrawalWithSignatureScript = new QueueWithdrawalWithSignatureScript();
        completeWithdrawalScript = new CompleteWithdrawalScript();

        testDeployVerifyScript = new TestDeployVerifyScript();

        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        vm.deal(deployer, 1 ether);
    }

    function test_step2_DeploySenderOnL2Script() public {
        deploySenderOnL2Script.testrun();
    }

    function test_step2b_UpgradeSenderOnL2Script() public {
        upgradeSenderOnL2Script.run();
    }

    // writes new json files: contract addrs
    function test_step3_DeployReceiverOnL1Script() public {
        deployReceiverOnL1Script.testrun();
    }

    // writes new json files: contract addrs
    function test_step3b_UpgradeReceiverOnL1Script() public {
        upgradeReceiverOnL1Script.testrun();
    }

    function test_step4_WhitelistCCIPContractsScript() public {
        whitelistCCIPContractsScript.run();
    }

    function test_step5_DepositWithSignatureScript() public {
        depositWithSignatureScript.run();
    }

    function test_step5b_MintEigenAgent() public {
        mintEigenAgentScript.run();
    }

    function test_step6_DelegateToScript() public {
        delegateToScript.run();
    }

    // writes new json files: withdrawalRoots
    function test_step7_QueueWithdrawalWithSignatureScript() public {
        queueWithdrawalWithSignatureScript.run();
    }

    function test_step8_CompleteWithdrawalScript() public {
        // requires step6 to be run first so that
        // script/withdrawals-queued/<eigen-agent-address>/run-latest.json exists
        completeWithdrawalScript.run();
    }

    function test_stepx_TestDeployVerify() public {
        testDeployVerifyScript.run();
    }
}

