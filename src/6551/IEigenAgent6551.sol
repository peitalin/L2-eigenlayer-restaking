// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

interface IEigenAgent6551 {

    function agentImplVersion() external returns (uint256);

    function getExecNonce() external view returns (uint256);

    function beforeExecute(bytes calldata data) external returns (bytes4);

    function afterExecute(
        bytes calldata data,
        bool success,
        bytes memory result
    ) external returns (bytes4);

    function executeWithSignature(
        address targetContract,
        uint256 value,
        bytes calldata data,
        uint256 expiry,
        bytes memory signature
    ) external payable returns (bytes memory result);

    function approveWithSignature(
        address targetContract,
        uint256 value,
        bytes calldata data,
        uint256 expiry,
        bytes memory signature
    ) external returns (bool);

    function approveByWhitelistedContract(
        address targetContract,
        address token,
        uint256 amount
    ) external returns (bool);

    function getAgentOwner() external view returns (address);

}
