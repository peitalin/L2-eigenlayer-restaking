// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";
import {UpgradeSenderOnL2Script} from "../script/2b_upgradeSenderOnL2.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {UpgradeReceiverOnL1Script} from "../script/3b_upgradeReceiverOnL1.s.sol";
import {WhitelistCCIPContractsScript} from "../script/4_whitelistCCIPContracts.s.sol";

import {DepositAndMintEigenAgentScript} from "../script/5_depositAndMintEigenAgent.s.sol";
import {DepositIntoStrategyScript} from "../script/5b_depositIntoStrategy.s.sol";
import {MintEigenAgentScript} from "../script/5c_mintEigenAgent.s.sol";
import {CheckMintEigenAgentGasCostsScript} from "../script/5d_checkMintEigenAgentGasCosts.s.sol";

import {DelegateToScript} from "../script/6_delegateTo.s.sol";
import {UndelegateScript} from "../script/6b_undelegate.s.sol";
import {RedepositScript} from "../script/6c_redeposit.s.sol";

import {QueueWithdrawalScript} from "../script/7_queueWithdrawal.s.sol";
import {CompleteWithdrawalScript} from "../script/8_completeWithdrawal.s.sol";
import {DeployVerifyScript} from "../script/x_deployVerify.s.sol";


contract DeployScriptsTests is Test {

    ///////////// Deploy scripts /////////////
    // 2
    DeploySenderOnL2Script public deploySenderOnL2Script;
    UpgradeSenderOnL2Script public upgradeSenderOnL2Script;
    // 3
    DeployReceiverOnL1Script public deployReceiverOnL1Script;
    UpgradeReceiverOnL1Script public upgradeReceiverOnL1Script;
    // 4
    WhitelistCCIPContractsScript public whitelistCCIPContractsScript;
    // 5
    DepositAndMintEigenAgentScript public depositAndMintEigenAgentScript;
    DepositIntoStrategyScript public depositIntoStrategyScript;
    MintEigenAgentScript public mintEigenAgentScript;
    CheckMintEigenAgentGasCostsScript public checkMintEigenAgentGasCostsScript;
    // 6
    DelegateToScript public delegateToScript;
    UndelegateScript public undelegateScript;
    RedepositScript public redepositScript;
    // 7
    QueueWithdrawalScript public queueWithdrawalScript;
    // 8
    CompleteWithdrawalScript public completeWithdrawalScript;
    // x
    DeployVerifyScript public deployerVerifyScript;

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    function setUp() public {

        deploySenderOnL2Script = new DeploySenderOnL2Script();
        upgradeSenderOnL2Script = new UpgradeSenderOnL2Script();

        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
        upgradeReceiverOnL1Script = new UpgradeReceiverOnL1Script();

        whitelistCCIPContractsScript = new WhitelistCCIPContractsScript();

        depositAndMintEigenAgentScript = new DepositAndMintEigenAgentScript();
        depositIntoStrategyScript = new DepositIntoStrategyScript();
        mintEigenAgentScript = new MintEigenAgentScript();
        checkMintEigenAgentGasCostsScript = new CheckMintEigenAgentGasCostsScript();

        delegateToScript = new DelegateToScript();
        undelegateScript = new UndelegateScript();
        redepositScript = new RedepositScript();

        queueWithdrawalScript = new QueueWithdrawalScript();
        completeWithdrawalScript = new CompleteWithdrawalScript();

        deployerVerifyScript = new DeployVerifyScript();

        vm.chainId(31337);
        vm.deal(deployer, 1 ether);
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_step2_DeploySenderOnL2Script() public {
        deploySenderOnL2Script.mockrun();
    }

    function test_step2b_UpgradeSenderOnL2Script() public {
        // This test fails if L2 contracts have not been deployed + saved to disk
        upgradeSenderOnL2Script.mockrun();
    }

    function test_step3_DeployReceiverOnL1Script() public {
        deployReceiverOnL1Script.mockrun();
        // Writes new json files: contract addrs
    }

    function test_step3b_UpgradeReceiverOnL1Script() public {
        // This test fails if L1 contracts have not been deployed + saved to disk
        upgradeReceiverOnL1Script.mockrun();
        // writes new json files: contract addrs
    }

    function test_step4_WhitelistCCIPContractsScript() public {
        whitelistCCIPContractsScript.mockrun();
    }

    function test_step5_DepositAndMintEigenAgentScript() public {
        // vm.assume(mockKey < type(uint256).max / 2);
        // vm.assume(mockKey > 1);
        // EIP-2: secp256k1 curve order / 2
        uint256 mockKey = (vm.randomUint() / 2) + 1;
        try depositAndMintEigenAgentScript.mockrun(mockKey) {
            //
        } catch Error(string memory reason) {
            compareErrorStr(reason, "User already has an EigenAgent");
        }
    }

    function test_step5b_DepositIntoStrategyScript() public {

        try depositIntoStrategyScript.mockrun() {
            //
        } catch Error(string memory reason) {
            compareErrorStr(reason, "User must have an EigenAgent");
        }
    }

    function test_step5c_MintEigenAgent() public {
        // vm.assume(mockKey < type(uint256).max / 2);
        // vm.assume(mockKey > 1);
        // EIP-2: secp256k1 curve order / 2
        uint256 mockKey = (vm.randomUint() / 2) + 1;
        mintEigenAgentScript.mockrun(mockKey);

        mintEigenAgentScript.run();
    }

    function test_step5d_CheckMintEigenAgentGasCosts() public {
        checkMintEigenAgentGasCostsScript.run();
    }

    function test_step6_DelegateToScript() public {

        try delegateToScript.mockrun() {
            //
        } catch Error(string memory reason) {
            compareErrorStr(reason, "User must have an EigenAgent");
        }
    }

    function test_step6b_UndelegateScript() public {
        try undelegateScript.mockrun() {
            //
        } catch (bytes memory err) {
            compareErrorBytes(err, "User must have an EigenAgent");
        }
    }

    function test_step6c_RedepositScript() public {
        try redepositScript.mockrun() {
            //
        } catch Error(string memory errStr) {
            compareErrorStr(errStr, "Withdrawals file not found");
            // Run undelegate script first
        } catch (bytes memory err) {
            compareErrorBytes(err, "User must have an EigenAgent");
        }
    }

    function test_step7_QueueWithdrawalScript() public {
        // Note: If step8 has completed withdrawal, this test may warn it failed with:
        // "revert: withdrawalRoot has already been used"
        queueWithdrawalScript.mockrun();
        // writes new json files: withdrawalRoots, so use mockrun()
    }

    function test_step8_CompleteWithdrawalScript() public {
        // Note: requires step7 to be run first so that:
        // script/withdrawals-queued/<eigen-agent-address>/run-latest.json exists
        try completeWithdrawalScript.mockrun() {

        } catch Error(string memory errStr) {
            compareErrorStr(errStr, "Withdrawals file not found");
            // Run undelegate scripts first
        } catch (bytes memory err) {
            compareErrorBytes(err, "User must have an EigenAgent");
        }
    }

    function test_stepx_TestDeployVerify() public {
        deployerVerifyScript.run();
    }

    function strEq(string memory s1, string memory s2) public pure returns (bool) {
        return keccak256(abi.encode(s1)) == keccak256(abi.encode(s2));
    }

    function compareErrorStr(string memory s1, string memory s2) public pure returns (bool) {
        if (strEq(s1, s2)) {
            console.log(s1);
        } else {
            revert(s1);
        }
    }

    function compareErrorBytes(bytes memory b1, string memory s2) public pure returns (bool) {
        string memory s1 = abi.decode(b1, (string));
        if (strEq(s1, s2)) {
            console.log(s1);
        } else {
            revert(s1);
        }
    }
}

