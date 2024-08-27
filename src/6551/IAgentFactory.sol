// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgent6551} from "./IEigenAgent6551.sol";
import {IEigenAgentOwner721} from "./IEigenAgentOwner721.sol";
import {IAdminable} from "../utils/Adminable.sol";



interface IAgentFactory is IAdminable {

    event EigenAgentOwnerUpdated(address indexed, address indexed, uint256 indexed);

    function getRestakingConnector() external view returns (address);

    function setRestakingConnector(address newRestakingConnector) external;

    function get6551Registry() external view returns (IERC6551Registry);

    function getEigenAgentOwner721() external view returns (IEigenAgentOwner721);

    function getEigenAgentOwnerTokenId(address staker) external view returns (uint256);

    function getEigenAgent(address staker) external view returns (IEigenAgent6551);

    function tryGetEigenAgentOrSpawn(address staker) external returns (IEigenAgent6551);

    function updateEigenAgentOwnerTokenId(
        address from,
        address to,
        uint256 tokenId
    ) external returns (uint256);

    function spawnEigenAgentOnlyOwner(address staker) external returns (IEigenAgent6551);

}