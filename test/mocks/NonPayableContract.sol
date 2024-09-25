// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

contract NonPayableContract {
    /// @notice Congtract with no receiver() or fallbacks() to test call{value: x ether}() failures
    // receive() external payable {}
    // fallback() external payable {}
}

