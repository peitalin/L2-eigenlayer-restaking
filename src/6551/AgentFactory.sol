// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

import {Adminable} from "../utils/Adminable.sol";
import {EigenlayerMsgDecoders} from "../utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "../utils/EigenlayerMsgEncoders.sol";
import {EigenlayerDeposit6551Msg} from "../utils/EigenlayerMsgDecoders.sol";
import {IRestakingConnector} from "../interfaces/IRestakingConnector.sol";

import {ERC6551AccountProxy} from "@6551/examples/upgradeable/ERC6551AccountProxy.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgent6551} from "./IEigenAgent6551.sol";
import {EigenAgent6551} from "./EigenAgent6551.sol";
import {IEigenAgentOwner721} from "./IEigenAgentOwner721.sol";
import {IAgentFactory} from "./IAgentFactory.sol";

import {console} from "forge-std/Test.sol";



contract AgentFactory is Adminable {

    error AddressZero(string msg);

    IERC6551Registry public erc6551Registry;
    IEigenAgentOwner721 public eigenAgentOwner721;
    address private _restakingConnector;

    mapping(address => uint256) public userToEigenAgentTokenIds;
    mapping(uint256 => address) public tokenIdToEigenAgents;

    /*
     *
     *                 Functions
     *
     *
     */

    constructor(
        IERC6551Registry _erc6551Registry,
        IEigenAgentOwner721 _eigenAgentOwner721
    ) {
        if (address(_erc6551Registry) == address(0))
            revert AddressZero("ERC6551Registry cannot be address(0)");

        if (address(_eigenAgentOwner721) == address(0))
            revert AddressZero("EigenAgentOwner721 cannot be address(0)");

        erc6551Registry = _erc6551Registry;
        eigenAgentOwner721 = _eigenAgentOwner721;

        __Adminable_init();
    }

    modifier onlyRestakingConnector() {
        console.log("msg.sender:", msg.sender);
        console.log("_restakingConnector:", _restakingConnector);
        require(msg.sender == _restakingConnector, "not called by RestakingConnector");
        _;
    }

    function getRestakingConnector() public view returns (address) {
        return _restakingConnector;
    }

    function setRestakingConnector(address newRestakingConnector) public onlyAdminOrOwner {
        if (address(newRestakingConnector) == address(0))
            revert AddressZero("AgentFactory.setRestakingConnector: cannot be address(0)");
        _restakingConnector = newRestakingConnector;
    }

    function get6551Registry() public view returns (IERC6551Registry) {
        return erc6551Registry;
    }

    function getEigenAgentOwner721() public view returns (IEigenAgentOwner721) {
        return eigenAgentOwner721;
    }

    function updateEigenAgentOwnerTokenId(
        address from,
        address to,
        uint256 tokenId
    ) external returns (uint256) {
        require(
            msg.sender == address(eigenAgentOwner721),
            "AgentFactory.updateEigenAgentOwnerTokenId: caller not EigenAgentOwner721 contract"
        );
        userToEigenAgentTokenIds[from] = 0;
        userToEigenAgentTokenIds[to] = tokenId;
        emit IAgentFactory.EigenAgentOwnerUpdated(from, to, tokenId);
    }

    function getEigenAgentOwnerTokenId(address staker) public view returns (uint256) {
        return userToEigenAgentTokenIds[staker];
    }

    function getEigenAgent(address staker) public view returns (address) {
        return tokenIdToEigenAgents[userToEigenAgentTokenIds[staker]];
    }

    function spawnEigenAgentOnlyOwner(
        address staker
    ) external onlyAdminOrOwner returns (IEigenAgent6551) {
        return _spawnEigenAgent6551(staker);
    }

    function tryGetEigenAgentOrSpawn(address staker)
        external onlyRestakingConnector
        returns (IEigenAgent6551)
    {
        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(getEigenAgent(staker)));
        if (address(eigenAgent) != address(0)) {
            return eigenAgent;
        }
        return _spawnEigenAgent6551(staker);
    }

    /// Mints an NFT and creates a 6551 account for it
    function _spawnEigenAgent6551(address staker) internal returns (IEigenAgent6551) {
        require(
            getEigenAgentOwnerTokenId(staker) == 0,
            "staker already has an EigenAgentOwner NFT"
        );
        require(
            getEigenAgent(staker) == address(0),
            "staker already has an EigenAgent account"
        );

        bytes32 salt = bytes32(abi.encode(staker));
        uint256 tokenId = eigenAgentOwner721.mint(staker);

        EigenAgent6551 eigenAgentImplementation = new EigenAgent6551();
        ERC6551AccountProxy eigenAgentProxy = new ERC6551AccountProxy(address(eigenAgentImplementation));

        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(
            erc6551Registry.createAccount(
                address(eigenAgentProxy),
                salt,
                block.chainid,
                address(eigenAgentOwner721),
                tokenId
            )
        ));

        userToEigenAgentTokenIds[staker] = tokenId;
        tokenIdToEigenAgents[tokenId] = address(eigenAgent);

        return eigenAgent;
    }
}