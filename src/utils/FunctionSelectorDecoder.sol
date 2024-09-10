// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

library FunctionSelectorDecoder {

    /// @dev Decodes leading bytes4 in the string message
    /// @param message is the CCIP Any2EVMMessage.data payload: an abi.encoded string
    function decodeFunctionSelector(bytes memory message)
        public
        pure
        returns (bytes4 functionSelector)
    {
        // CCIP abi.encodes(string(message)) wraps messages adding 64 bytes),
        // so functionSelector begins at 96
        assembly {
            // string_offset := mload(add(message, 32))
            // string_length := mload(add(message, 64))
            functionSelector := mload(add(message, 96))
        }
    }

    /// @dev decodes error selectors. Used to catch EigenAgentExecutionError to refund failed deposits on L1.
    function decodeErrorSelector(bytes memory customError)
        public
        pure
        returns (bytes4 errorSelector)
    {
        //////////////////////// Message offsets //////////////////////////
        // [59b170e3]0000000000000000000000004ef1575822436f6fc6935aa3f025c7ea [32]
        // bytes4 takes the leading 4 bytes of the 32 byte word.
        assembly {
            errorSelector := mload(add(customError, 32))
        }
    }

    /**
     * @dev decodes params associated with EigenAgentExecutionError
     * @return signer the original signer of the message
     * @return expiry signature expiry
     */
    function decodeEigenAgentExecutionErrorParams(bytes memory customError)
        public
        pure
        returns (address signer, uint256 expiry)
    {
        //////////////////////// Message offsets //////////////////////////
        // 59b170e3                                                         [32]
        // 0000000000000000000000004ef1575822436f6fc6935aa3f025c7eaedce67a4 [36] signer
        // 0000000000000000000000000000000000000000000000000000000066dc8444 [68] expiry

        assembly {
            // errorSelector := mload(add(customError, 32))
            signer := mload(add(customError, 36))
            expiry := mload(add(customError, 68))
        }
    }
}

