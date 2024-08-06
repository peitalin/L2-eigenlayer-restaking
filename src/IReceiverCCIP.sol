// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IRestakingConnector} from "./IRestakingConnector.sol";

interface IReceiverCCIP {

    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external;

    function allowlistSourceChain(uint64 _sourceChainSelector, bool allowed) external;

    function allowlistSender(address _sender, bool allowed) external;

    function mockCCIPReceive(Client.Any2EVMMessage memory any2EvmMessage) external;

    function getRestakingConnector() external returns (IRestakingConnector);

    function sendMessagePayLINK(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount
    ) external returns (bytes32 messageId);

    function sendMessagePayNative(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        address _token,
        uint256 _amount
    ) external returns (bytes32 messageId);

    function getLastReceivedMessageDetails() external view returns (
        bytes32 messageId,
        string memory text,
        address tokenAddress,
        uint256 tokenAmount
    );

    function withdraw(address _beneficiary) external;

    function withdrawToken(address _beneficiary, address _token) external;
}

