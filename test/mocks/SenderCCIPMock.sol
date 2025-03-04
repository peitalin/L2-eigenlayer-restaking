// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {SenderCCIP} from "../../src/SenderCCIP.sol";
import {ISenderCCIP} from "../../src/interfaces/ISenderCCIP.sol";

interface ISenderCCIPMock is ISenderCCIP {
    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) external;

    function mockBuildCCIPMessage(
        address _receiver,
        string calldata _text,
        Client.EVMTokenAmount[] memory _tokenAmounts,
        address _feeTokenAddress,
        uint256 _overrideGasLimit
    ) external returns (Client.EVM2AnyMessage memory);
}

contract SenderCCIPMock is SenderCCIP {

    constructor(address _router) SenderCCIP(_router) {}

    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) public {
        _ccipReceive(any2EvmMessage);
    }

    function mockBuildCCIPMessage(
        address _receiver,
        string calldata _text,
        Client.EVMTokenAmount[] memory _tokenAmounts,
        address _feeTokenAddress,
        uint256 _overrideGasLimit
    ) public returns (Client.EVM2AnyMessage memory) {
        _buildCCIPMessage(_receiver, _text, _tokenAmounts, _feeTokenAddress, _overrideGasLimit);
    }
}

