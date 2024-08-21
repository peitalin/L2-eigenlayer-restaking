// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IEigenlayerMsgDecoders} from "./IEigenlayerMsgDecoders.sol";

interface ISenderUtils is IEigenlayerMsgDecoders {

    function decodeFunctionSelector(bytes memory message) external returns (bytes4);

    function setGasLimitsForFunctionSelectors(bytes4 functionSelector, uint256 gasLimit) external;

    function getGasLimitForFunctionSelector(bytes4 functionSelector) external returns (uint256);

    function setFunctionSelectorName(bytes4 functionSelector, string memory _name) external;

    function getFunctionSelectorName(bytes4 functionSelector) external returns (string memory);
}


