// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    IERC6551Executable,
    IERC6551Account as IERC6551
} from "@6551/examples/simple/ERC6551Account.sol";


interface IEigenAgent6551 is IERC6551, IERC6551Executable {

    error CallerNotWhitelisted(string reason);
    error SignatureInvalid(string reason);
    error RestakingConnectorAlreadyInitialized();
    error AddressZero(string reason);

    function execNonce() external view returns (uint256);

    function EIGEN_AGENT_EXEC_TYPEHASH() external returns (bytes32);

    function owner() external view returns (address);

    function token() external view returns (
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    );

    function approveByWhitelistedContract(
        address targetContract,
        address token,
        uint256 amount
    ) external;

    function executeWithSignature(
        address targetContract,
        uint256 value,
        bytes calldata data,
        uint256 expiry,
        bytes memory signature
    ) external payable returns (bytes memory result);

    function isValidSignature(
        bytes32 digestHash,
        bytes memory signature
    ) external view returns (bytes4);

    function createEigenAgentCallDigestHash(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 nonce,
        uint256 chainid,
        uint256 expiry
    ) external view returns (bytes32);

    function domainSeparator(uint256 chainid) external view returns (bytes32);

    function supportsInterface(bytes4 interfaceId) external pure returns (bool);

    function restakingConnector() external view returns (address);

    function setInitialRestakingConnector(address _restakingConnector) external;
}
