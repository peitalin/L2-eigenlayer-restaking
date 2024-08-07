
// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";

interface IStrategyManagerDomain is IStrategyManager {

    // this public function is defined in StrategyManager.sol, but not in IStrategyManager.sol
    function domainSeparator() external view returns (bytes32);

}