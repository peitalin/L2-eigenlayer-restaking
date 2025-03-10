// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BytesLib} from "./BytesLib.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";


library FunctionSelectorDecoder {

    /// @dev Decodes leading bytes4 in the string message
    /// @param message is the CCIP Any2EVMMessage.data payload: an abi.encoded string
    function decodeFunctionSelector(bytes memory message)
        public
        pure
        returns (bytes4 functionSelector)
    {
        // CCIP abi.encodes(string(message)) messages, adding 64 bytes. functionSelector begins at 0x60 (96)
        assembly {
            // string_offset := mload(add(message, 0x20))
            // string_length := mload(add(message, 0x40))
            functionSelector := mload(add(message, 0x60))
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
            errorSelector := mload(add(customError, 0x20))
        }
    }

    /**
     * @dev Decodes a nested error message from EigenAgent: EigenAgentExecutionError(signer, expiry, Error(string))
     * and bubbles them up the callstack for better UX.
     * @return signer the original signer of the message
     * @return expiry signature expiry
     */
    function decodeEigenAgentExecutionError(bytes memory customError)
        public
        pure
        returns (address signer, uint256 expiry, string memory reason)
    {
        //////////////////////// Message offsets //////////////////////////
        // (A) When EigenAgent throws a custom Error(string) like SignatureInvalid(string)
        // or from require(bool, string) or revert(string) statements from Eigenlayer:
        //
        // 2fe80af8                                                         [32] outer error selector (EigenAgentExecutionError)
        // 000000000000000000000000ba068c4d5a557417f50482b29e50699ac5fa25af [36] signer
        // 0000000000000000000000000000000000000000000000000000000066ea28d4 [68] expiry
        // 0000000000000000000000000000000000000000000000000000000000000060 [100] string offset
        // 00000000000000000000000000000000000000000000000000000000000000a4 [132] string length
        // 08c379a0                                                         [136] inner error selector: "Error(string)"
        // 0000000000000000000000000000000000000000000000000000000000000020 [168] inner error offset
        // 000000000000000000000000000000000000000000000000000000000000004d [200] inner error length (starts here)
        // 53747261746567794d616e616765722e6f6e6c79537472617465676965735768 [232] inner error message begins
        // 6974656c6973746564466f724465706f7369743a207374726174656779206e6f [264]
        // 742077686974656c697374656400000000000000000000000000000000000000 [296]
        // 00000000000000000000000000000000000000000000000000000000
        //
        // (B) When EigenAgent throws a custom Error() error with no string, len == 164
        // 2fe80af8
        // 000000000000000000000000a6ab3a612722d5126b160eef5b337b8a04a76dd8 [36]
        // 000000000000000000000000000000000000000000000000000000000000003d [68]
        // 0000000000000000000000000000000000000000000000000000000000000060 [100]
        // 0000000000000000000000000000000000000000000000000000000000000004 [132]
        // 37e8456b                                                         [136]
        // 00000000000000000000000000000000000000000000000000000000         [164]

        assembly {
            signer := mload(add(customError, 36))
            expiry := mload(add(customError, 68))
        }

        if (customError.length > 164) {

            uint32 innerErrorSelector; // uint32 = 4 bytes
            assembly {
                innerErrorSelector := mload(add(customError, 136))
                // alternatively, use bytes4 from offset 164
            }

            // Check error selector matches valid Error(string) selectors.
            if (
                innerErrorSelector == 0x08c379a0    // Error(string)
                || innerErrorSelector == 0xc2a21d1d // CallerNotWhitelisted(string)
                || innerErrorSelector == 0xad62b3ea // SignatureInvalid(string)
                || innerErrorSelector == 0x3fc42773 // TooManyTokensToDeposit(string)
                || innerErrorSelector == 0x790929a2 // TokenAmountMismatch(string)
            ) {
                uint32 innerErrorLength;
                uint32 innerErrorOffset = 200;
                // Error string length always exists for Error(string) and starts on offset 200.
                assembly {
                    innerErrorLength := mload(add(customError, innerErrorOffset))
                }
                // Check length of the remaining customError message is longer than innerErrorLength,
                // so that we are safe to parse (memory safe).
                require(customError.length - innerErrorOffset >= innerErrorLength, "Invalid Error(string)");
                reason = string(_decodeInnerError(customError, innerErrorOffset));
            } else {
                // Return error selector for other custom errors
                reason = Strings.toHexString(uint256(uint32(innerErrorSelector)), 4);
            }
        }

        /////////////////////////////
        /// Eigenlayer Custom Errors
        /////////////////////////////
        if (customError.length == 164) {

            uint32 innerErrorSelector; // uint32 = 4 bytes
            assembly {
                innerErrorSelector := mload(add(customError, 136))
                // alternatively, use bytes4 from offset 164
            }

            reason = parseEigenlayerError(innerErrorSelector);
        }

    }

    /// @dev Decodes the inner Error(string) in EigenAgentExecutionError(signer, expiry, Error(string))
    function _decodeInnerError(bytes memory customError, uint32 errMessageOffset)
        private
        pure
        returns (bytes memory errBytes)
    {
        // customError is dynamic-sized byte array, the first 32 bit of the pointer stores the length of it.
        uint32 errLength;
        assembly {
            errLength := mload(add(customError, errMessageOffset))
        }

        bytes memory errPacked = new bytes(errLength);

        assembly {
            // mcopy is only available in solc ^0.8.24
            mcopy(
                // Add +32 bytes to skip 1st line (length)
                add(errPacked, 0x20),
                add(customError, add(errMessageOffset, 0x20)),
                errLength
            )
        }
        return BytesLib.slice(errPacked, 0, errLength);

        //// Alternatively if using solc < 0.8.24
        //
        // // Round up to nearest 32, then divided by 32 to get number of lines the error string takes
        // uint32 numErrLines = (errLength - errLength % 32 + 32) / 32 ;
        // bytes32[] memory errStringArray = new bytes32[](numErrLines);
        //
        // for (uint32 i = 0; i < numErrLines; ++i) {
        //     bytes32 _errLine;
        //     uint32 offset = errMessageOffset + 32 + i*32;
        //     // Add +32 bytes to skip 1st line (length), then loop through error string lines with i*32
        //     assembly {
        //         _errLine := mload(add(customError, offset))
        //     }
        //     errStringArray[i] = _errLine;
        // }
        // // Pack the error bytestrings together, and slice off trailing 0s.
        // bytes memory errPacked = abi.encodePacked(errStringArray);
        // errBytes = BytesLib.slice(errPacked, 0, errLength);
    }

    function parseEigenlayerError(uint32 errorSelector) private pure returns (string memory reason) {
        // IStrategyManagerErrors
        if (errorSelector == 0x5dfb2ca2) {
            reason = "StrategyNotWhitelisted()";

        } else if (errorSelector == 0x0d0a21c8) {
            reason = "MaxStrategiesExceeded()";

        } else if (errorSelector == 0xf739589b) {
            reason = "OnlyDelegationManager()";

        } else if (errorSelector == 0x82e8ffe4) {
            reason = "OnlyStrategyWhitelister()";

        } else if (errorSelector == 0x4b18b193) {
            reason = "SharesAmountTooHigh()";

        } else if (errorSelector == 0x840c364a) {
            reason = "SharesAmountZero()";

        } else if (errorSelector == 0x16f2ccc9) {
            reason = "StakerAddressZero()";

        } else if (errorSelector == 0x5be2b482) {
            reason = "StrategyNotFound()";

        // DelegationManager errors
        } else if (errorSelector == 0x11481a94) {
            reason = "OnlyStrategyManagerOrEigenPodManager()";

        } else if (errorSelector == 0xc84e9984) {
            reason = "OnlyEigenPodManager()";

        } else if (errorSelector == 0x23d871a5) {
            reason = "OnlyAllocationManager()";

        } else if (errorSelector == 0x8e5199a8) {
            reason = "OperatorsCannotUndelegate()";

        } else if (errorSelector == 0x77e56a06) {
            reason = "ActivelyDelegated()";

        } else if (errorSelector == 0xa5c7c445) {
            reason = "NotActivelyDelegated()";

        } else if (errorSelector == 0x25ec6c1f) {
            reason = "OperatorNotRegistered()";

        } else if (errorSelector == 0x87c9d219) {
            reason = "WithdrawalNotQueued()";

        } else if (errorSelector == 0x3c933446) {
            reason = "CallerCannotUndelegate()";

        } else if (errorSelector == 0x43714afd) {
            reason = "InputArrayLengthMismatch()";

        } else if (errorSelector == 0x796cc525) {
            reason = "InputArrayLengthZero()";

        } else if (errorSelector == 0x28cef1a4) {
            reason = "FullySlashed()";

        } else if (errorSelector == 0x35313244) {
            reason = "SaltSpent()";

        } else if (errorSelector == 0xf1ecf5c2) {
            reason = "WithdrawalDelayNotElapsed()";

        } else if (errorSelector == 0x584434d4) {
            reason = "WithdrawerNotCaller()";

        // RewardsCoordinator errors (not comprehensive)
        } else if (errorSelector == 0x5c427cd9) {
            reason = "UnauthorizedCaller()";

        } else if (errorSelector == 0xfb494ea1) {
            reason = "InvalidEarner()";

        } else if (errorSelector == 0x10c748a6) {
            reason = "InvalidAddressZero()";

        } else if (errorSelector == 0x504570e3) {
            reason = "InvalidRoot()";

        } else if (errorSelector == 0x94a8d389) {
            reason = "InvalidRootIndex()";

        } else if (errorSelector == 0x796cc525) {
            reason = "InputArrayLengthZero()";

        } else if (errorSelector == 0x43714afd) {
            reason = "InputArrayLengthMismatch()";

        } else if (errorSelector == 0x729f942c) {
            reason = "NewRootMustBeForNewCalculatedPeriod()";

        } else if (errorSelector == 0x0d2af922) {
            reason = "RewardsEndTimestampNotElapsed()";

        } else if (errorSelector == 0x7ec5c154) {
            reason = "InvalidOperatorSet()";

        } else if (errorSelector == 0x43ad20fc) {
            reason = "AmountIsZero()";

        } else if (errorSelector == 0x1c2d69bc) {
            reason = "AmountExceedsMax()";

        } else if (errorSelector == 0x891c63df) {
            reason = "SplitExceedsMax()";

        } else if (errorSelector == 0x7b1e25c5) {
            reason = "PreviousSplitPending()";

        } else if (errorSelector == 0x3742e7d4) {
            reason = "DurationExceedsMax()";

        } else if (errorSelector == 0xcb3f434d) {
            reason = "DurationIsZero()";

        } else if (errorSelector == 0xee664705) {
            reason = "InvalidDurationRemainder()";

        } else if (errorSelector == 0x0e06bd31) {
            reason = "InvalidGenesisRewardsTimestampRemainder()";

        } else if (errorSelector == 0x4478f672) {
            reason = "InvalidCalculationIntervalSecondsRemainder()";

        } else if (errorSelector == 0xf06a53c4) {
            reason = "InvalidStartTimestampRemainder()";

        } else if (errorSelector == 0x7ee2b443) {
            reason = "StartTimestampTooFarInFuture()";

        } else {
            reason = Strings.toHexString(uint256(uint32(errorSelector)), 4);
        }
    }
}



