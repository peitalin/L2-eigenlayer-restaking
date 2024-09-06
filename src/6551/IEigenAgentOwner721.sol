// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;


import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Adminable, IAdminable} from "../utils/Adminable.sol";
import {IAgentFactory} from "../6551/IAgentFactory.sol";


interface IEigenAgentOwner721 is IAdminable, IERC721 {

    function getAgentFactory() external returns (address);

    function setAgentFactory(IAgentFactory _agentFactory) external;

    function isWhitelistedCaller(address caller) external returns (bool);

    function addToWhitelistedCallers(address caller) external;

    function removeFromWhitelistedCallers(address caller) external;

    function mint(address user) external returns (uint256);

    function mintOnlyOwner(address user) external returns (uint256);

}
