// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from "@openzeppelin-v5-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-v5-contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Clones} from "@openzeppelin-v5-contracts/proxy/Clones.sol";

import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgent6551} from "./IEigenAgent6551.sol";
import {EigenAgent6551} from "./EigenAgent6551.sol";
import {IEigenAgentOwner721} from "./IEigenAgentOwner721.sol";
import {IAgentFactory} from "./IAgentFactory.sol";
import {Adminable} from "../utils/Adminable.sol";



contract AgentFactory is Initializable, Adminable, ReentrancyGuardUpgradeable {

    IERC6551Registry public erc6551Registry;
    IEigenAgentOwner721 public eigenAgentOwner721;
    address public baseEigenAgent;
    address private _restakingConnector;

    mapping(address => uint256) public userToEigenAgentTokenIds;
    mapping(uint256 => address) public tokenIdToEigenAgents;

    event SetRestakingConnector(address indexed);
    event Set6551Registry(IERC6551Registry indexed);
    event SetEigenAgentOwner721(IEigenAgentOwner721 indexed);
    event AgentCreated(
        address indexed owner,
        address indexed eigenAgent,
        uint256 indexed tokenId
    );

    error AddressZero(string msg);

    /*
     *
     *                 Functions
     *
     *
     */

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC6551Registry _erc6551Registry,
        IEigenAgentOwner721 _eigenAgentOwner721,
        address _baseEigenAgent
    ) external initializer {

        if (address(_erc6551Registry) == address(0))
            revert AddressZero("_erc6551Registry cannot be address(0)");

        if (address(_eigenAgentOwner721) == address(0))
            revert AddressZero("_eigenAgentOwner721 cannot be address(0)");

        if (_baseEigenAgent == address(0))
            revert AddressZero("_baseEigenAgent cannot be address(0)");

        erc6551Registry = _erc6551Registry;
        eigenAgentOwner721 = _eigenAgentOwner721;
        baseEigenAgent = _baseEigenAgent;

        __Adminable_init();
        __ReentrancyGuard_init();
    }

    modifier onlyRestakingConnector() {
        require(msg.sender == _restakingConnector, "AgentFactory: not called by RestakingConnector");
        _;
    }

    function getRestakingConnector() external view returns (address) {
        return _restakingConnector;
    }

    /// @param newRestakingConnector address of the RestakingConnector contract.
    function setRestakingConnector(address newRestakingConnector) external onlyAdminOrOwner {
        if (address(newRestakingConnector) == address(0))
            revert AddressZero("AgentFactory.setRestakingConnector: cannot be address(0)");

        _restakingConnector = newRestakingConnector;
        emit SetRestakingConnector(newRestakingConnector);
    }

    /// @param new6551Registry address of the 6551Registry contract.
    function set6551Registry(IERC6551Registry new6551Registry) external onlyAdminOrOwner {
        if (address(new6551Registry) == address(0))
            revert AddressZero("AgentFactory.set6551Registry: cannot be address(0)");

        erc6551Registry = new6551Registry;
        emit Set6551Registry(new6551Registry);
    }

    /// @param newEigenAgentOwner721 address of the eigenAgentOwner712 NFT contract.
    function setEigenAgentOwner721(IEigenAgentOwner721 newEigenAgentOwner721) external onlyAdminOrOwner {
        if (address(newEigenAgentOwner721) == address(0))
            revert AddressZero("AgentFactory.setEigenAgentOwner721: cannot be address(0)");

        eigenAgentOwner721 = newEigenAgentOwner721;
        emit SetEigenAgentOwner721(newEigenAgentOwner721);
    }

    /**
     * @dev Gets the tokenId of the EigenAgentOwner NFT owned by the user.
     * Owner of the NFT controls the associated 6551v EigenAgent account.
     * @param user owner of the EigenAgentOwner NFT
     */
    function getEigenAgentOwnerTokenId(address user) external view returns (uint256) {
        return userToEigenAgentTokenIds[user];
    }

    /**
     * @dev Tries to get a user's 6551 EigenAgent account if they have one, or spawns a new EigenAgent
     * for the user if they do not already have one. Mind the gas costs is higher if they need to mint.
     * @param user address to retrive (or spawn) their ERC-6551 EigenAgent account.
     */
    function tryGetEigenAgentOrSpawn(address user)
        external
        onlyRestakingConnector
        returns (IEigenAgent6551)
    {
        IEigenAgent6551 eigenAgent = getEigenAgent(user);
        if (address(eigenAgent) != address(0)) {
            return eigenAgent;
        }
        return _spawnEigenAgent6551(user);
    }

    /**
     * @dev Spawns a ERC-6551 EigenAgent for a user.
     * @param user address to mint a EigenAgentOwner721 NFT and create a ERC-6551 EigenAgent account for.
     */
    function spawnEigenAgentOnlyOwner(address user)
        external
        onlyAdminOrOwner
        returns (IEigenAgent6551)
    {
        return _spawnEigenAgent6551(user);
    }

    /**
     * @dev This callback is triggered every time a EigenAgentOwner721 NFT is transferred.
     * @param from the account where NFT is being transferred from
     * @param to the account where NFT is being transferred to
     * @param tokenId NFT tokenId is being transferred
     */
    function updateEigenAgentOwnerTokenId(
        address from,
        address to,
        uint256 tokenId
    ) external {
        require(
            msg.sender == address(eigenAgentOwner721),
            "AgentFactory.updateEigenAgentOwnerTokenId: caller not EigenAgentOwner721 contract"
        );
        userToEigenAgentTokenIds[from] = 0;
        userToEigenAgentTokenIds[to] = tokenId;
        emit IAgentFactory.EigenAgentOwnerUpdated(from, to, tokenId);
    }

    /**
     * @dev Gets the ERC-6551 EigenAgent account of the user.
     * @param user owner of the EigenAgentOwner NFT that controls the ERC-6551 EigenAgent account.
     */
    function getEigenAgent(address user) public view returns (IEigenAgent6551) {
        return IEigenAgent6551(payable(tokenIdToEigenAgents[userToEigenAgentTokenIds[user]]));
    }

    /**
     * @dev Mints a EigenAgentOnwer721 NFT and creates a ERC-6551 EigenAgent account for it.
     * The resulting ERC-6551 EigenAgent account address is deterministic and depends on
     * (1) the user's address, (2) chainId, (3) Eigenagent6551 implementation contract,
     * (4) contract address of EigenAgentOwner721 NFT, and (5) tokenId of the EigenAgentOwner NFT.
     * @param user the address to spawn an EigenAgent 6551 account and EigenAgentOwner721 NFT for.
     */
    function _spawnEigenAgent6551(address user) private nonReentrant returns (IEigenAgent6551) {

        require(eigenAgentOwner721.balanceOf(user) == 0, "User already has an EigenAgent");
        // if the user transfers their AgentOwnerNft they can mint another one.

        uint256 tokenId = eigenAgentOwner721.mint(user);
        // userToEigenAgentTokenIds[user] = tokenId is set in EigenAgentOwner721._afterTokenTransfer
        bytes32 salt2 = keccak256(abi.encodePacked(tokenId));

        // Clone the baseEigenAgent
        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(
            erc6551Registry.createAccount(
                Clones.cloneDeterministic(baseEigenAgent, salt2), // ERC-1167 minimal viable proxy clone
                salt2,
                block.chainid,
                address(eigenAgentOwner721),
                tokenId
            )
        ));

        // set the RestakingConnector on the new EigenAgent
        eigenAgent.setInitialRestakingConnector(_restakingConnector);

        tokenIdToEigenAgents[tokenId] = address(eigenAgent);

        emit AgentCreated(user, address(eigenAgent), tokenId);

        return eigenAgent;
    }

    function predictEigenAgentAddress(address user, uint256 userTokenIdNonce) external view returns (address) {
        uint256 predictedTokenId = eigenAgentOwner721.predictTokenId(user, userTokenIdNonce);
        bytes32 salt2 = keccak256(abi.encodePacked(predictedTokenId));
        return erc6551Registry.account(
            Clones.predictDeterministicAddress(baseEigenAgent, salt2, address(this)),
            salt2,
            block.chainid,
            address(eigenAgentOwner721),
            predictedTokenId
        );
    }
}