// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IBaseMessengerCCIP} from "./IBaseMessengerCCIP.sol";

interface ISenderCCIP is IBaseMessengerCCIP {

    function setGasLimitsForFunctionSelectors(bytes4 functionSelector, uint256 gasLimit) external;
}

