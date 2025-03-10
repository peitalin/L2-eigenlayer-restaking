// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC721} from "@openzeppelin-v5-contracts/token/ERC721/IERC721.sol";
import {IAdminable} from "../utils/Adminable.sol";
import {IAgentFactory} from "../6551/IAgentFactory.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";


interface IEigenAgentOwner721 is IAdminable, IERC721 {

    function getAgentFactory() external returns (address);

    function setAgentFactory(IAgentFactory _agentFactory) external;

    function getRewardsCoordinator() external returns (address);

    function setRewardsCoordinator(IRewardsCoordinator _rewardsCoordinator) external;

    function isWhitelistedCaller(address caller) external returns (bool);

    function addToWhitelistedCallers(address caller) external;

    function removeFromWhitelistedCallers(address caller) external;

    function mint(address user) external returns (uint256);

    function predictTokenId(address user, uint256 userTokenIdNonce) external view returns (uint256);
}
