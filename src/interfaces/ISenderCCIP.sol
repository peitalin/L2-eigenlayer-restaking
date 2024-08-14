// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IBaseMessengerCCIP} from "./IBaseMessengerCCIP.sol";

interface ISenderCCIP is IBaseMessengerCCIP {

    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) external;

    function setGasLimitsForFunctionSelectors(bytes4 functionSelector, uint256 gasLimit) external;
}

