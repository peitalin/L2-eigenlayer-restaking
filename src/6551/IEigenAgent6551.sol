// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

// import {IERC6551Account} from "@6551/examples/simple/ERC6551Account.sol";
import {IERC6551Account} from "./ERC6551Account.sol";

interface IEigenAgent6551 is IERC6551Account {

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

    function getAgentOwner() external view returns (address);

}
