// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Adminable} from "../utils/Adminable.sol";
import {IAgentFactory} from "./IAgentFactory.sol";


contract EigenAgentOwner721 is Initializable, ERC721URIStorageUpgradeable, Adminable {

    uint256 private _tokenIdCounter;
    IAgentFactory public agentFactory;

    mapping(address contracts => bool whitelisted) public whitelistedCallers;

    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name, string memory symbol) external initializer {

        __ERC721_init(name, symbol);
        __ERC721URIStorage_init();
        __Adminable_init();

        _tokenIdCounter = 1;
    }

    modifier onlyAgentFactory() {
        require(msg.sender == address(agentFactory), "Caller not AgentFactory");
        _;
    }

    function getAgentFactory() external view returns (address) {
        return address(agentFactory);
    }

    /// @param _agentFactory is the AgentFactory contract that creates EigenAgents
    function setAgentFactory(IAgentFactory _agentFactory) external onlyAdminOrOwner {
        require(address(_agentFactory) != address(0), "AgentFactory cannot be address(0)");
        agentFactory = _agentFactory;
    }

    /**
     * @dev Whitelists the RestakingConnector contract to allow it to approve token spends
     * for EigenAgents. Specifically, RestakingConnector approves Eigenlayer StrategyManager to
     * transferFrom tokens into Eigenlayer Strategy vaults.
     * This whitelist is only used in the function EigenAgent6551.approveByWhitelistedContract().
     * @param caller is the contract to whitelist (RestakingConnector)
     */
    function addToWhitelistedCallers(address caller) external onlyAdminOrOwner {
        whitelistedCallers[caller] = true;
    }

    /// @param caller is the contract to remove from whitelist.
    function removeFromWhitelistedCallers(address caller) external onlyAdminOrOwner {
        whitelistedCallers[caller] = false;
    }

    function isWhitelistedCaller(address caller) external view returns (bool) {
        return whitelistedCallers[caller];
    }

    function mint(address user) external onlyAgentFactory returns (uint256) {
        return _mint(user);
    }

    function _mint(address user) internal returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        ++_tokenIdCounter;
        _safeMint(user, tokenId);
        _setTokenURI(tokenId, string(abi.encodePacked("eigen-agent/", Strings.toString(tokenId), ".json")));
        return tokenId;
    }

    /**
     * @dev Hook to update EigenAgentOwner721 NFT owner whenever a NFT transfer occurs.
     * This updates AgentFactory and keeps users matched with tokenIds (and associated ERC-6551 EigenAgents).
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override virtual {
        require(balanceOf(to) <= 1, "Cannot own more than one EigenAgentOwner721 at a time.");
        agentFactory.updateEigenAgentOwnerTokenId(from, to, tokenId);
    }
}
