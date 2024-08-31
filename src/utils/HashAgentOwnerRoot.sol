//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

library HashAgentOwnerRoot {
    function hashAgentOwnerRoot(bytes32 withdrawalRoot, address agentOwner) public pure returns (bytes32) {
        return keccak256(abi.encode(withdrawalRoot, agentOwner));
    }
}
