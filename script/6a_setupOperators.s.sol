// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer-contracts/interfaces/ISignatureUtilsMixin.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {BaseScript} from "./BaseScript.sol";
import {EthSepolia} from "./Addresses.sol";


contract SetupOperatorsScript is BaseScript {

    uint256 deployerKey;
    address deployer;

    uint256 operatorKey1;
    address operator1;
    uint256 operatorKey2;
    address operator2;

    address staker;
    address TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

    function run() public {
        return _run(false);
    }

    function mockrun() public {
        return _run(true);
    }

    function _run(bool isTest) private {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        readContractsAndSetupEnvironment(isTest, deployer);

        TARGET_CONTRACT = address(delegationManager);

        //////////////////////////////////////////////////////////
        // L1: Register Operator
        //////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        operatorKey1 = vm.envUint("OPERATOR_KEY1");
        operator1 = vm.addr(operatorKey1);

        operatorKey2 = vm.envUint("OPERATOR_KEY2");
        operator2 = vm.addr(operatorKey2);

        console.log("operator1:", operator1);
        console.log("operator2:", operator2);

        if (operator1.balance == 0 ether) {
            if (isTest) {
                vm.deal(operator1, 0.05 ether);
            } else {
                revert("Operator1 has no balance");
            }
        }
        if (operator2.balance == 0 ether) {
            if (isTest) {
                vm.deal(operator2, 0.05 ether);
            } else {
                revert("Operator2 has no balance");
            }
        }

        if (!delegationManager.isOperator(operator1) || isTest) {
            vm.startBroadcast(operatorKey1);
            {
                string memory metadataURI = "L2 Restaking Operator";
                try delegationManager.registerAsOperator(
                    operator1,  // initDelegationApprover
                    10, // allocationDelay
                    metadataURI // metadataURI
                ) {
                    // success
                } catch Panic(uint256 reason) {
                    console.log(reason);
                } catch Error(string memory reason) {
                    console.log(reason); // registerAsOperator: caller is already actively delegated
                }
            }
            vm.stopBroadcast();
        }

        if (!delegationManager.isOperator(operator2) || isTest) {
            vm.startBroadcast(operatorKey2);
            {
                string memory metadataURI2 = "L2 Restaking Operator2";
                try delegationManager.registerAsOperator(
                    operator2,  // initDelegationApprover
                    10, // allocationDelay
                    metadataURI2 // metadataURI
                ) {
                    // success
                } catch Panic(uint256 reason) {
                    console.log(reason);
                } catch Error(string memory reason) {
                    console.log(reason); // registerAsOperator: caller is already actively delegated
                }
            }
            vm.stopBroadcast();
        }
    }
}
