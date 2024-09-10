// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {DeployScriptHelpers} from "./DeployScriptHelpers.sol";

import {DepositAndMintEigenAgentScript} from "../script/5_depositAndMintEigenAgent.s.sol";
import {DepositIntoStrategyScript} from "../script/5b_depositIntoStrategy.s.sol";
import {MintEigenAgentScript} from "../script/5c_mintEigenAgent.s.sol";
import {CheckMintEigenAgentGasCostsScript} from "../script/5d_checkMintEigenAgentGasCosts.s.sol";
import {QueueWithdrawalScript} from "../script/7_queueWithdrawal.s.sol";
import {CompleteWithdrawalScript} from "../script/8_completeWithdrawal.s.sol";


contract DepositWithdrawalScriptsTests is Test, DeployScriptHelpers {

    function setUp() public {}

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_step5_DepositAndMintEigenAgentScript() public {

        DepositAndMintEigenAgentScript depositAndMintEigenAgentScript =
            new DepositAndMintEigenAgentScript();

        // vm.assume(mockKey < type(uint256).max / 2);
        // vm.assume(mockKey > 1);
        // EIP-2: secp256k1 curve order / 2
        uint256 mockKey = (vm.randomUint() / 3) + 2;
        try depositAndMintEigenAgentScript.mockrun(mockKey) {
            //
        } catch Error(string memory reason) {
            catchErrorStr(reason, "User already has an EigenAgent");
        }
    }

    function test_step5b_DepositIntoStrategyScript() public {

        DepositIntoStrategyScript depositIntoStrategyScript = new DepositIntoStrategyScript();

        try depositIntoStrategyScript.mockrun() {
            //
        } catch Error(string memory reason) {
            catchErrorStr(reason, "User must have an EigenAgent");
        }
    }

    function test_step5c_MintEigenAgent() public {

        MintEigenAgentScript mintEigenAgentScript = new MintEigenAgentScript();
        // vm.assume(mockKey < type(uint256).max / 2);
        // vm.assume(mockKey > 1);
        // EIP-2: secp256k1 curve order / 2
        uint256 mockKey = (vm.randomUint() / 2) + 1;
        mintEigenAgentScript.mockrun(mockKey);

        mintEigenAgentScript.run();
    }

    function test_step5d_CheckMintEigenAgentGasCosts() public {

        CheckMintEigenAgentGasCostsScript checkMintEigenAgentGasCostsScript
            = new CheckMintEigenAgentGasCostsScript();

        checkMintEigenAgentGasCostsScript.mockrun();
    }

    function test_step7_QueueWithdrawalScript() public {

        QueueWithdrawalScript queueWithdrawalScript = new QueueWithdrawalScript();
        // Note: If step8 has completed withdrawal, this test may warn it failed with:
        // "revert: withdrawalRoot has already been used"
        queueWithdrawalScript.mockrun();
        // writes new json files: withdrawalRoots, so use mockrun()
    }

    function test_step8_CompleteWithdrawalScript() public {

        CompleteWithdrawalScript completeWithdrawalScript = new CompleteWithdrawalScript();
        // Note: requires step7 to be run first so that:
        // script/withdrawals-queued/<eigen-agent-address>/run-latest.json exists
        try completeWithdrawalScript.mockrun() {
            //
        } catch Error(string memory errStr) {
            if (catchErrorStr(errStr, "User must have an EigenAgent")) {
                console.log("Run depositAndMintEigenAgent script first.");

            } else if (catchErrorStr(errStr, "Withdrawals file not found")) {
                console.log("Run queueWithdrawal script first.");

            } else {
                revert(errStr);
            }
        }

    }
}

