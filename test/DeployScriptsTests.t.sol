// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";

import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";
import {UpgradeSenderOnL2Script} from "../script/2b_upgradeSenderOnL2.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {UpgradeReceiverOnL1Script} from "../script/3b_upgradeReceiverOnL1.s.sol";
import {WhitelistCCIPContractsScript} from "../script/4_whitelistCCIPContracts.s.sol";
import {DepositWithSignatureScript} from "../script/5_depositWithSignature.s.sol";
import {DelegateToScript} from "../script/6_delegateTo.s.sol";
import {QueueWithdrawalWithSignatureScript} from "../script/7_queueWithdrawalWithSignature.s.sol";
import {CompleteWithdrawalScript} from "../script/8_completeWithdrawal.s.sol";
import {ScriptUtils} from "../script/ScriptUtils.sol";


contract DeployScriptsTests is Test, ScriptUtils {

    // deploy scripts
    DeploySenderOnL2Script public deploySenderOnL2Script;
    UpgradeSenderOnL2Script public upgradeSenderOnL2Script;

    DeployReceiverOnL1Script public deployOnEthScript;
    UpgradeReceiverOnL1Script public upgradeReceiverOnL1Script;

    WhitelistCCIPContractsScript public whitelistCCIPContractsScript;
    DepositWithSignatureScript public depositWithSignatureScript;
    DelegateToScript public delegateToScript;

    QueueWithdrawalWithSignatureScript public queueWithdrawalWithSignatureScript;
    CompleteWithdrawalScript public completeWithdrawalScript;

    uint256 public deployerKey;
    address public deployer;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deploySenderOnL2Script = new DeploySenderOnL2Script();
        upgradeSenderOnL2Script = new UpgradeSenderOnL2Script();

        deployOnEthScript = new DeployReceiverOnL1Script();
        upgradeReceiverOnL1Script = new UpgradeReceiverOnL1Script();

        whitelistCCIPContractsScript = new WhitelistCCIPContractsScript();

        depositWithSignatureScript = new DepositWithSignatureScript();

        delegateToScript = new DelegateToScript();

        queueWithdrawalWithSignatureScript = new QueueWithdrawalWithSignatureScript();
        completeWithdrawalScript = new CompleteWithdrawalScript();

        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        vm.deal(deployer, 1 ether);
    }

    function test_step2_DeploySenderOnL2Script() public {
        deploySenderOnL2Script.run();
    }

    function test_step2b_UpgradeSenderOnL2Script() public {
        upgradeSenderOnL2Script.run();
    }

    function test_step3_DeployReceiverOnL1Script() public {
        deployOnEthScript.run();
    }

    function test_step3b_UpgradeReceiverOnL1Script() public {
        upgradeReceiverOnL1Script.run();
    }

    function test_step4_WhitelistCCIPContractsScript() public {
        whitelistCCIPContractsScript.run();
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

