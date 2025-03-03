// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721URIStorageUpgradeable} from "@openzeppelin-v5-contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {Initializable} from "@openzeppelin-v5-contracts-upgradeable/proxy/utils/Initializable.sol";
import {Strings} from "@openzeppelin-v5-contracts/utils/Strings.sol";

import {Adminable} from "../utils/Adminable.sol";
import {IAgentFactory} from "./IAgentFactory.sol";


contract EigenAgentOwner721 is Initializable, ERC721URIStorageUpgradeable, Adminable {

    IAgentFactory public agentFactory;

    mapping(address contracts => bool whitelisted) public whitelistedCallers;

    /// Keeps track of user mintNonces for deterministic tokenId generation
    mapping(address user => uint256 mintNonce) public userTokenIdNonces;

    event AddToWhitelistedCallers(address indexed caller);
    event RemoveFromWhitelistedCallers(address indexed caller);
    event SetAgentFactory(address indexed agentFactory);

    error AlreadyHasAgent(address owner);

    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name, string memory symbol) external initializer {

        __ERC721_init(name, symbol);
        __ERC721URIStorage_init();
        __Adminable_init();
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
        emit SetAgentFactory(address(_agentFactory));
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
        emit AddToWhitelistedCallers(caller);
    }

    /// @param caller is the contract to remove from whitelist.
    function removeFromWhitelistedCallers(address caller) external onlyAdminOrOwner {
        whitelistedCallers[caller] = false;
        emit RemoveFromWhitelistedCallers(caller);
    }

    function isWhitelistedCaller(address caller) external view returns (bool) {
        return whitelistedCallers[caller];
    }

    function mint(address user) external onlyAgentFactory returns (uint256) {
        return _mint(user);
    }

    function _mint(address user) internal returns (uint256) {
        uint256 tokenId = _createTokenId(user);
        _safeMint(user, tokenId);
        return tokenId;
    }

    function _createTokenId(address user) internal returns (uint256) {
        uint256 nextNonce = userTokenIdNonces[user];
        // Increment the nonce for this user
        ++userTokenIdNonces[user];
        uint256 tokenId = predictTokenId(user, nextNonce);
        return tokenId;
    }

    function predictTokenId(address user, uint256 userTokenIdNonce) public pure returns (uint256) {
        // keccak256 hash user and userTokenIdNonce to ensure unique but deterministic tokenId
        bytes32 fullHash = keccak256(abi.encodePacked(user, userTokenIdNonce));
        // Shorten tokenId to the last 6 bytes (12 hex digits) by masking with 0xFFFFFFFFFFFF
        // Convert to uint256 first to do the bitwise operation, then back to bytes32
        bytes32 maskedHash = bytes32(uint256(fullHash) & 0xFFFFFFFFFFFF);
        // Convert the bytes32 to uint256 for the tokenId
        uint256 tokenId = uint256(maskedHash);
        // Make sure tokenId is never zero by adding 1 if needed
        if (tokenId == 0) {
            ++tokenId;
        }
        return tokenId;
    }


    /**
     * @dev Update EigenAgentOwner721 NFT owner whenever a NFT transfer occurs.
     * This updates AgentFactory and keeps users matched with tokenIds (and associated ERC-6551 EigenAgents).
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = super._update(to, tokenId, auth);
        require(balanceOf(to) <= 1, "Cannot own more than one EigenAgentOwner721 at a time.");
        agentFactory.updateEigenAgentOwnerTokenId(from, to, tokenId);
        return from;
    }

}
