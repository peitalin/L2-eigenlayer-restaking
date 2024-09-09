// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {DeployScriptHelpers} from "./DeployScriptHelpers.sol";

import {DelegateToScript} from "../script/6_delegateTo.s.sol";
import {UndelegateScript} from "../script/6b_undelegate.s.sol";
import {RedepositScript} from "../script/6c_redeposit.s.sol";



contract DelegationScriptsTests is Test, DeployScriptHelpers {

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
            compareErrorStr(reason, "User must have an EigenAgent");
        }
    }

    function test_step6b_UndelegateScript() public {

        UndelegateScript undelegateScript = new UndelegateScript();

        try undelegateScript.mockrun() {
            //
        } catch (bytes memory err) {
            compareErrorBytes(err, "User must have an EigenAgent");
        }
    }

    function test_step6c_RedepositScript() public {

        RedepositScript redepositScript = new RedepositScript();

        try redepositScript.mockrun() {
            //
        } catch Error(string memory errStr) {
            compareErrorStr(errStr, "Withdrawals file not found");
            // Run undelegate script first on Sepolia.
        } catch (bytes memory err) {
            compareErrorBytes(err, "User must have an EigenAgent");
        }
    }

}

