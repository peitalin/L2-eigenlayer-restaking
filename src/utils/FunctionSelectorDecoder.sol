// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

library FunctionSelectorDecoder {

    /// @dev Decodes leading bytes4 in the string message
    /// @param message is the CCIP Any2EVMMessage.data payload: an abi.encoded string
    function decodeFunctionSelector(bytes memory message) public pure returns (bytes4) {

        bytes32 offset; // string offset
        bytes32 length; // string length
        bytes4 functionSelector; // leading 4 bytes of the message

        assembly {
            offset := mload(add(message, 32))
            length := mload(add(message, 64))
            functionSelector := mload(add(message, 96))
        }

        return functionSelector;
    }

}

