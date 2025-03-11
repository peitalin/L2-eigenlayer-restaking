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

    uint256 operatorKey;
    address operator;
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

        operatorKey = vm.envUint("OPERATOR_KEY");
        operator = vm.addr(operatorKey);

        if (!delegationManager.isOperator(operator) || isTest) {
            vm.startBroadcast(operatorKey);
            {
                string memory metadataURI = "some operator";
                try delegationManager.registerAsOperator(
                    operator,  // initDelegationApprover
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
    }
}
