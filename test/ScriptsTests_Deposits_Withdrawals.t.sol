// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {TestErrorHandlers} from "./TestErrorHandlers.sol";

import {DepositAndMintEigenAgentScript} from "../script/5_depositAndMintEigenAgent.s.sol";
import {DepositIntoStrategyScript} from "../script/5b_depositIntoStrategy.s.sol";
import {MintEigenAgentScript} from "../script/5c_mintEigenAgent.s.sol";
import {CheckMintEigenAgentGasCostsScript} from "../script/5d_checkMintEigenAgentGasCosts.s.sol";
import {QueueWithdrawalScript} from "../script/7_queueWithdrawal.s.sol";
import {CompleteWithdrawalScript} from "../script/8_completeWithdrawal.s.sol";


contract ScriptsTests_Deposits_Withdrawals is Test, TestErrorHandlers {

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
        uint256 mockKey = (vm.randomUint() / 2) + 1;
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
        uint256 mockKey = (vm.randomUint() / 2) + 1;
        // vm.assume(mockKey < type(uint256).max / 2);
        // vm.assume(mockKey > 1);
        // EIP-2: secp256k1 curve order / 2
        try mintEigenAgentScript.mockrun(mockKey) {
            //
        } catch Error(string memory reason) {
            if (catchErrorStr(reason, "Not admin or owner")) {
                console.log("Run deploy scripts 2 and 3 first.");
            } else {
                revert(reason);
            }
        }
    }

    function test_step5d_CheckMintEigenAgentGasCosts() public {

        CheckMintEigenAgentGasCostsScript checkMintEigenAgentGasCostsScript
            = new CheckMintEigenAgentGasCostsScript();

        try checkMintEigenAgentGasCostsScript.mockrun() {
            //
        } catch Error(string memory reason) {
            if (catchErrorStr(reason, "Not admin or owner")) {
                console.log("Run deploy scripts 2 and 3 first.");
            } else {
                revert(reason);
            }
        }
    }

    function test_step7_QueueWithdrawalScript() public {

        QueueWithdrawalScript queueWithdrawalScript = new QueueWithdrawalScript();
        // Writes new json files: withdrawalRoots, so use mockrun()
        try queueWithdrawalScript.mockrun() {
        //
        } catch Error(string memory errStr) {
            if (catchErrorStr(errStr, "User must have an EigenAgent")) {
                console.log("Run depositAndMintEigenAgent script first.");

            } else if (catchErrorStr(errStr, "SenderHooks._commitWithdrawalTransferRootInfo: TransferRoot already used")) {
                // Note: If step8 has completed withdrawal, this test may warn it failed with:
                // "SenderHooks._commitWithdrawalTransferRootInfo: TransferRoot already used"
                console.log("Make another deposit first, run depositAndMintEigenAgent script.");
            } else {
                revert(errStr);
            }
        }
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

