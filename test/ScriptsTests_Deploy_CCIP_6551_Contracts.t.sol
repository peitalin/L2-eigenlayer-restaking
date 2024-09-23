// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {TestErrorHandlers} from "./TestErrorHandlers.sol";

import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";
import {UpgradeSenderOnL2Script} from "../script/2b_upgradeSenderOnL2.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {UpgradeReceiverOnL1Script} from "../script/3b_upgradeReceiverOnL1.s.sol";
import {WhitelistCCIPContractsScript} from "../script/4_whitelistCCIPContracts.s.sol";


contract ScriptsTests_Deploy_CCIP_6551_Contracts is Test, TestErrorHandlers {

    function setUp() public {}

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_step2_DeploySenderOnL2Script() public {

        DeploySenderOnL2Script deploySenderOnL2Script = new DeploySenderOnL2Script();

        deploySenderOnL2Script.mockrun();
    }

    function test_step2b_UpgradeSenderOnL2Script() public {

        UpgradeSenderOnL2Script upgradeSenderOnL2Script = new UpgradeSenderOnL2Script();
        // This test fails if L2 contracts have not been deployed + saved to disk
        try upgradeSenderOnL2Script.mockrun() {
            //
        } catch Error(string memory reason) {
            if (catchErrorStr(reason, "Ownable: caller is not the owner")) {
                console.log("Run deploy script 2 first.");
            } else {
                revert(reason);
            }
        }
    }

    function test_step3_DeployReceiverOnL1Script() public {

        DeployReceiverOnL1Script deployReceiverOnL1Script =
            new DeployReceiverOnL1Script();

        deployReceiverOnL1Script.mockrun();
        // Writes new json files: contract addrs
    }

    function test_step3b_UpgradeReceiverOnL1Script() public {

        UpgradeReceiverOnL1Script upgradeReceiverOnL1Script =
            new UpgradeReceiverOnL1Script();

        // This test fails if L1 contracts have not been deployed + saved to disk
        // writes new json files: contract addrs
        try upgradeReceiverOnL1Script.mockrun() {
            //
        } catch Error(string memory reason) {
            if (catchErrorStr(reason, "Ownable: caller is not the owner")) {
                console.log("Run deploy script 3 first.");
            } else {
                revert(reason);
            }
        }
    }

    function test_step4_WhitelistCCIPContractsScript() public {

        WhitelistCCIPContractsScript whitelistCCIPContractsScript =
            new WhitelistCCIPContractsScript();

        try whitelistCCIPContractsScript.mockrun() {
            //
        } catch Error(string memory reason) {
            if (catchErrorStr(reason, "Ownable: caller is not the owner")) {
                console.log("Run deploy scripts 2 and 3 first.");
            } else {
                revert(reason);
            }
        }
    }

}

