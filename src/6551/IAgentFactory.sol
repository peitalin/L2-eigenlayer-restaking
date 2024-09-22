// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgent6551} from "./IEigenAgent6551.sol";
import {IEigenAgentOwner721} from "./IEigenAgentOwner721.sol";
import {IAdminable} from "../utils/Adminable.sol";



interface IAgentFactory is IAdminable {

    event EigenAgentOwnerUpdated(address indexed, address indexed, uint256 indexed);

    function erc6551Registry() external view returns (IERC6551Registry);

    function eigenAgentOwner721() external view returns (IEigenAgentOwner721);

    function baseEigenAgent() external view returns (address);

    function getRestakingConnector() external view returns (address);

    function setRestakingConnector(address newRestakingConnector) external;

    function set6551Registry(IERC6551Registry new6551Registry) external;

    function setEigenAgentOwner721(IEigenAgentOwner721 newEigenAgentOwner721) external;

    function getEigenAgentOwnerTokenId(address staker) external view returns (uint256);

    function tryGetEigenAgentOrSpawn(address staker) external returns (IEigenAgent6551);

    function spawnEigenAgentOnlyOwner(address staker) external returns (IEigenAgent6551);

    function updateEigenAgentOwnerTokenId(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function getEigenAgent(address staker) external view returns (IEigenAgent6551);

}