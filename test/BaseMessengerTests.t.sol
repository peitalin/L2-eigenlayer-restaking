// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {BaseMessengerCCIP} from "../src/BaseMessengerCCIP.sol";
import {EigenlayerMsgDecoders} from "../src/utils/EigenlayerMsgDecoders.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";


contract BaseMessenger_Tests is BaseTestEnvironment {

    uint256 expiry;
    uint256 amount;

    function setUp() public {
        // setup forked environments for L2 and L1 contracts
        setUpForkedEnvironment();
        // call params
        amount = 0.0028 ether;
        expiry = block.timestamp + 1 days;
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_BaseMeseenger_Allowlists() public {

        vm.selectFork(ethForkId);

        uint256 execNonce = 0;
        bytes memory messageWithSignature;
        bytes memory message = encodeMintEigenAgent(bob);

    }


}