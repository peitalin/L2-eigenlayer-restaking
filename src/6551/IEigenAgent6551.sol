// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IBase6551Account} from "./Base6551Account.sol";


interface IEigenAgent6551 is IBase6551Account {

    function EIGEN_AGENT_EXEC_TYPEHASH() external returns (bytes32);

    function DOMAIN_TYPEHASH() external returns (bytes32);

    function isValidSignature(
        bytes32 digestHash,
        bytes memory signature
    ) external view returns (bytes4);

    function executeWithSignature(
        address targetContract,
        uint256 value,
        bytes calldata data,
        uint256 expiry,
        bytes memory signature
    ) external payable returns (bytes memory result);

    function approveByWhitelistedContract(
        address targetContract,
        address token,
        uint256 amount
    ) external returns (bool);

    function execNonce() external view returns (uint256);

    function owner() external view returns (address) ;

    function createEigenAgentCallDigestHash(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 chainid,
        uint256 expiry
    ) external pure returns (bytes32);

    function domainSeparator(
        address contractAddr,
        uint256 chainid
    ) external pure returns (bytes32);
}
