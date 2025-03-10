// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Client} from "@chainlink/ccip/libraries/Client.sol";

interface IBaseMessengerCCIP {

    function allowlistDestinationChain(uint64 _destinationChainSelector, bool allowed) external;

    function allowlistSourceChain(uint64 _sourceChainSelector, bool allowed) external;

    function allowlistSender(uint64 _sourceChainSelector, address _sender, bool allowed) external;

    function allowlistedDestinationChains(uint64 _destinationChainSelector) external returns (bool);

    function allowlistedSourceChains(uint64 _sourceChainSelector) external returns (bool);

    function allowlistedSenders(uint64 _sourceChainSelector, address _sender) external returns (bool);

    function sendMessagePayNative(
        uint64 _destinationChainSelector,
        address _receiver,
        string calldata _text,
        Client.EVMTokenAmount[] memory _tokenAmounts,
        uint256 _overrideGasLimit
    ) external payable returns (bytes32 messageId);

    function withdraw(address _beneficiary, uint256 _amount) external;

    function withdrawToken(address _beneficiary, address _token, uint256 _amount) external;

    function bridgeTokenL1() external returns (address);

    function bridgeTokenL2() external returns (address);

    function setBridgeTokens(address _bridgeTokenL1, address _bridgeTokenL2) external;
}

