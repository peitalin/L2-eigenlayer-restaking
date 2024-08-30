// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, stdJson, console} from "forge-std/Script.sol";
import {EmptyContract} from "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";


contract TestDeployVerifyScript is Script {

    uint256 private deployerKey = vm.envUint("DEPLOYER_KEY");
    address public deployer = vm.addr(deployerKey);

    function run() public {
        vm.startBroadcast(deployerKey);
        EmptyContract empty = new EmptyContract();
        empty.foo();
        vm.stopBroadcast();
    }
}