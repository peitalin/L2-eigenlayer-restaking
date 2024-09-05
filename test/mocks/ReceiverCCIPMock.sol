// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {ReceiverCCIP} from "../../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../../src/interfaces/IReceiverCCIP.sol";

interface IReceiverCCIPMock is IReceiverCCIP {
    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) external;
}

contract ReceiverCCIPMock is ReceiverCCIP {

    constructor(address _router, address _link) ReceiverCCIP(_router, _link) {}

    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) public {
        _ccipReceive(any2EvmMessage);
    }
}

