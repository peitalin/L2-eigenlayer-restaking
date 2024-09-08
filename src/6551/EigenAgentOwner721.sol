// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Adminable} from "../utils/Adminable.sol";
import {IAgentFactory} from "./IAgentFactory.sol";


contract EigenAgentOwner721 is Initializable, ERC721URIStorageUpgradeable, Adminable {

    uint256 private _tokenIdCounter;
    IAgentFactory public agentFactory;

    mapping(address contracts => bool whitelisted) public whitelistedCallers;

    function initialize(string memory name, string memory symbol) initializer public {

        __ERC721_init(name, symbol);
        __ERC721URIStorage_init();
        __Adminable_init();

        _tokenIdCounter = 1;
    }

    function addToWhitelistedCallers(address caller) external onlyAdminOrOwner {
        whitelistedCallers[caller] = true;
    }

    function removeFromWhitelistedCallers(address caller) external onlyAdminOrOwner {
        whitelistedCallers[caller] = false;
    }

    function isWhitelistedCaller(address caller) public view returns (bool) {
        return whitelistedCallers[caller];
    }

    function getAgentFactory() public view returns (address) {
        return address(agentFactory);
    }

    function setAgentFactory(IAgentFactory _agentFactory) public onlyAdminOrOwner {
        require(address(_agentFactory) != address(0), "AgentFactory cannot be address(0)");
        agentFactory = _agentFactory;
    }

    modifier onlyAgentFactory() {
        require(msg.sender == address(agentFactory), "Caller not AgentFactory");
        _;
    }

    function mint(address user) public onlyAgentFactory returns (uint256) {
        return _mint(user);
    }

    function _mint(address user) internal returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        ++_tokenIdCounter;
        _safeMint(user, tokenId);
        _setTokenURI(tokenId, string(abi.encodePacked("eigen-agent/", Strings.toString(tokenId), ".json")));
        return tokenId;
    }

    /// @dev callback to update EigenAgentOwner721 NFT owner.
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override virtual {
        agentFactory.updateEigenAgentOwnerTokenId(from, to, tokenId);
    }
}
