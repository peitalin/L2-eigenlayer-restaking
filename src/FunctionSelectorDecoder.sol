// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

contract FunctionSelectorDecoder {

    event MessengerDecodedFunctionSelector(
        bytes4 indexed functionSelector,
        address indexed contractAddr
    );

    /// @dev Decodes leading bytes4 in the string message to know how to decode the rest of the message
    /// @param message is the CCIP Any2EVMMessage.data payload: an abi.encoded string
    function decodeFunctionSelector(bytes memory message) public returns (bytes4) {
        bytes32 offset; // string offset
        bytes32 length; // string length
        bytes4 functionSelector; // leading 4 bytes of the message

        assembly {
            offset := mload(add(message, 32))
            length := mload(add(message, 64))
            functionSelector := mload(add(message, 96))
        }

        // Note: production logging, can remove for gas
        emit MessengerDecodedFunctionSelector(functionSelector, address(this));

        return functionSelector;
    }
}

