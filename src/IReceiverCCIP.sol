// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRestakingConnector} from "./IRestakingConnector.sol";
import {ISenderCCIP} from "./ISenderCCIP.sol";

// inherits from ISenderCCIP.sol which we use as base
interface IReceiverCCIP is ISenderCCIP {

    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) external;

    function getRestakingConnector() external returns (IRestakingConnector);

}

