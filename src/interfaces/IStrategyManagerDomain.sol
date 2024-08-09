
// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
// import {StrategyManagerStorage} from "eigenlayer-contracts/src/contracts/core/StrategyManagerStorage.sol";
// import {StrategyManager} from "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";

interface IStrategyManagerDomain is IStrategyManager {

    // this public function is publicly defined in StrategyManager.sol, but not in IStrategyManager.sol
    function domainSeparator() external view returns (bytes32);

    // nonces: mapping is publicly defined in StrategyManagerStorage.sol, but not in IStrategyManager.sol
    function nonces(address sender) external view returns (uint256);

}