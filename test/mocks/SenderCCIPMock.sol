// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {SenderCCIP} from "../../src/SenderCCIP.sol";
import {ISenderCCIP} from "../../src/interfaces/ISenderCCIP.sol";

interface ISenderCCIPMock is ISenderCCIP {
    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) external;
    function setBridgeTokens(address _bridgeTokenL1, address _bridgeTokenL2) external;
}

contract SenderCCIPMock is SenderCCIP {

    constructor(
        address _router,
        address _bridgeTokenL1,
        address _bridgeTokenL2
    ) SenderCCIP(_router, _bridgeTokenL1, _bridgeTokenL2) {}

    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) public {
        _ccipReceive(any2EvmMessage);
    }
}

