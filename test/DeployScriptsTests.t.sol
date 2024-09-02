// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";
import {UpgradeSenderOnL2Script} from "../script/2b_upgradeSenderOnL2.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {UpgradeReceiverOnL1Script} from "../script/3b_upgradeReceiverOnL1.s.sol";
import {WhitelistCCIPContractsScript} from "../script/4_whitelistCCIPContracts.s.sol";
import {DepositWithSignatureScript} from "../script/5_depositWithSignature.s.sol";
import {MintEigenAgentScript} from "../script/5b_mintEigenAgent.s.sol";
import {CheckMintEigenAgentGasCostsScript} from "../script/5c_checkMintEigenAgentGasCosts.s.sol";

import {DelegateToScript} from "../script/6_delegateTo.s.sol";
import {UndelegateScript} from "../script/6b_undelegate.s.sol";
import {RedepositScript} from "../script/6c_redeposit.s.sol";

import {QueueWithdrawalWithSignatureScript} from "../script/7_queueWithdrawalWithSignature.s.sol";
import {CompleteWithdrawalScript} from "../script/8_completeWithdrawal.s.sol";
import {DeployVerifyScript} from "../script/x_deployVerify.s.sol";
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
    CheckMintEigenAgentGasCostsScript public checkMintEigenAgentGasCostsScript;

    DelegateToScript public delegateToScript;
    UndelegateScript public undelegateScript;
    RedepositScript public redepositScript;

    QueueWithdrawalWithSignatureScript public queueWithdrawalWithSignatureScript;
    CompleteWithdrawalScript public completeWithdrawalScript;

    DeployVerifyScript public deployerVerifyScript;

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    function setUp() public {

        deploySenderOnL2Script = new DeploySenderOnL2Script();
        upgradeSenderOnL2Script = new UpgradeSenderOnL2Script();

        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
        upgradeReceiverOnL1Script = new UpgradeReceiverOnL1Script();

        whitelistCCIPContractsScript = new WhitelistCCIPContractsScript();

        depositWithSignatureScript = new DepositWithSignatureScript();
        mintEigenAgentScript = new MintEigenAgentScript();
        checkMintEigenAgentGasCostsScript = new CheckMintEigenAgentGasCostsScript();

        delegateToScript = new DelegateToScript();
        undelegateScript = new UndelegateScript();
        redepositScript = new RedepositScript();

        queueWithdrawalWithSignatureScript = new QueueWithdrawalWithSignatureScript();
        completeWithdrawalScript = new CompleteWithdrawalScript();

        deployerVerifyScript = new DeployVerifyScript();

        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        vm.deal(deployer, 1 ether);
    }

    function test_step2_DeploySenderOnL2Script() public {
        deploySenderOnL2Script.mockrun();
    }

    function test_step2b_UpgradeSenderOnL2Script() public {
        // this test fails if L2 contracts have not been deployed + saved to disk
        upgradeSenderOnL2Script.mockrun();
    }

    function test_step3_DeployReceiverOnL1Script() public {
        deployReceiverOnL1Script.mockrun();
        // writes new json files: contract addrs
    }

    function test_step3b_UpgradeReceiverOnL1Script() public {
        // this test fails if L1 contracts have not been deployed + saved to disk
        upgradeReceiverOnL1Script.mockrun();
        // writes new json files: contract addrs
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

    function test_step5c_CheckMintEigenAgentGasCosts() public {
        checkMintEigenAgentGasCostsScript.run();
    }

    function test_step6_DelegateToScript() public {
        delegateToScript.run();
    }

    function test_step6b_UndelegateScript() public {
        try undelegateScript.mockrun() {
            //
        } catch Error(string memory reason) {
            if (strEq(reason, "eigenAgent not delegatedTo operator")) {
                console.log("undelegateScript: must run 6_delegateTo.s.sol script first");
            } else {
                console.log(reason);
            }
        } catch (bytes memory reason) {
            revert(abi.decode(reason, (string)));
        }
    }

    function test_step6c_RedepositScript() public {
        try redepositScript.mockrun() {
            //
        } catch Error(string memory reason) {
            // vm.expectRevert("eigenAgent not delegatedTo operator");
            if (strEq(reason, "eigenAgent not delegatedTo operator")) {
                console.log("redepositScript: must run 6b_undelegate.s.sol script first");
            } else {
                console.log(reason);
            }
        } catch (bytes memory reason) {
            revert(abi.decode(reason, (string)));
        }
    }

    function test_step7_QueueWithdrawalWithSignatureScript() public {
        // Note II: If step8 has completed withdrawal, this test may warn it failed with:
        // "revert: withdrawalRoot has already been used"
        queueWithdrawalWithSignatureScript.run();
        // writes new json files: withdrawalRoots
    }

    function test_step8_CompleteWithdrawalScript() public {
        // Note: requires step7 to be run first so that:
        // script/withdrawals-queued/<eigen-agent-address>/run-latest.json exists
        completeWithdrawalScript.mockrun();
    }

    function test_stepx_TestDeployVerify() public {
        deployerVerifyScript.run();
    }

    function strEq(string memory s1, string memory s2) public pure returns (bool) {
        return keccak256(abi.encode(s1)) == keccak256(abi.encode(s2));
    }
}

