// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {TestErrorHandlers} from "./TestErrorHandlers.sol";

import {DelegateToScript} from "../script/6_delegateTo.s.sol";
import {UndelegateScript} from "../script/6b_undelegate.s.sol";
import {RedepositScript} from "../script/6c_redeposit.s.sol";

import {SubmitRewardsScript} from "../script/9_submitRewards.s.sol";
import {ProcessClaimRewardsScript} from "../script/9b_processClaimRewards.s.sol";



contract ScriptsTests_Delegation_Rewards is Test, TestErrorHandlers {

    function setUp() public {}

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_step6_DelegateToScript() public {

        DelegateToScript delegateToScript = new DelegateToScript();

        try delegateToScript.mockrun() {
            //
        } catch Error(string memory reason) {
            catchErrorStr(reason, "User must have an EigenAgent");
        }
    }

    function test_step6b_UndelegateScript() public {

        UndelegateScript undelegateScript = new UndelegateScript();

        try undelegateScript.mockrun() {
            //
        } catch (bytes memory err) {
            //
        } catch Error(string memory errStr) {
            if (catchErrorStr(errStr, "Withdrawals file not found")) {

            } else if (catchErrorStr(errStr, "User must have an EigenAgent")) {
                console.log("Run depositAndMintEigenAgent script first");

            } else if (catchErrorStr(errStr, "EigenAgent has no deposit in Eigenlayer")) {
                console.log("Run depositIntoStrategy script first");

            } else if (catchErrorStr(errStr, "Operator must be registered")) {
                console.log("Run delegateTo script first");

            } else if (catchErrorStr(errStr, "EigenAgent not delegatedTo any operators")) {
                console.log("Run delegateTo script first");

            } else {
                revert(errStr);
            }
        }

    }

    function test_step6c_RedepositScript() public {

        RedepositScript redepositScript = new RedepositScript();

        try redepositScript.mockrun() {
            //
        } catch Error(string memory errStr) {

            if (catchErrorStr(errStr, "User must have an EigenAgent")) {
                console.log("Run depositAndMintEigenAgent script first");

            } else if (catchErrorStr(errStr, "Withdrawals file not found")) {
                console.log("Run undelegate script first");

            } else {
                revert(errStr);
            }
        }
    }

    function test_step9_SubmitRewardsScript() public {

        SubmitRewardsScript submitRewardsScript = new SubmitRewardsScript();

        try submitRewardsScript.mockrun() {
            //
        } catch Error(string memory errStr) {

            if (catchErrorStr(errStr, "RewardsCoordinator.submitRoot: new root must be for newer calculated period")) {
                console.log("Rewards root already submitted for this week.");
            } else {
                revert(errStr);
            }
        }
    }

    function test_step9b_ProcessClaimRewardsScript() public {

        ProcessClaimRewardsScript processClaimRewardsScript = new ProcessClaimRewardsScript();

        try processClaimRewardsScript.mockrun() {
            //
        } catch Error(string memory errStr) {
            if (catchErrorStr(errStr, "RewardsCoordinator.processClaim: cumulativeEarnings must be gt than cumulativeClaimed")) {
                console.log("Already claimed. Submit another RewardRoot before trying to claim.");

            } else if (catchErrorStr(errStr, "RewardsCoordinator._verifyEarnerClaimProof: invalid earner claim proof")) {
                console.log("Either an invalid claim, or run script 9 and submit a root first.");

            } else {
                revert(errStr);
            }
        }
    }
}

