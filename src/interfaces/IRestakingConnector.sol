// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IEigenlayerMsgDecoders} from "../interfaces/IEigenlayerMsgDecoders.sol";

import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgent6551} from "../../src/6551/IEigenAgent6551.sol";
import {EigenAgentOwner721} from "../../src/6551/EigenAgentOwner721.sol";
import {ERC6551AccountProxy} from "@6551/examples/upgradeable/ERC6551AccountProxy.sol";


interface IRestakingConnector is IEigenlayerMsgDecoders {

    /*
     *
     *              L1->L2 Transfer Handler
     *
     *
    */

    function encodeHandleTransferToAgentOwnerMsg(
        bytes32 withdrawalRoot,
        address agentOwner
    ) external returns (bytes memory);

    /*
     *
     *                EigenAgent Functions
     *
     *
    */

    function get6551Registry() external view returns (IERC6551Registry);

    function getEigenAgentOwner721() external view returns (EigenAgentOwner721);

    function getEigenAgentOwnerTokenId(address staker) external view returns (uint256);

    function getEigenAgent(address staker) external view returns (address);

    function updateEigenAgentOwnerTokenId(
        address from,
        address to,
        uint256 tokenId
    ) external returns (uint256);

    function spawnEigenAgentOnlyOwner(address staker) external returns (IEigenAgent6551);

    /*
     *
     *                EigenAgent -> Eigenlayer Handlers
     *
     *
    */

    function depositWithEigenAgent(bytes memory message, address token, uint256 amount) external;

    function queueWithdrawalsWithEigenAgent(bytes memory message, address token, uint256 amount) external;

    function completeWithdrawalWithEigenAgent(
        bytes memory message,
        address token,
        uint256 amount
    ) external returns (
        IDelegationManager.Withdrawal memory,
        string memory // CCIP message for transferToAgentOwner on L2
    );

    function delegateToWithEigenAgent(bytes memory message, address token, uint256 amount) external;

    /*
     *
     *                Eigenlayer Functions
     *
     *
    */

    function getEigenlayerContracts() external returns (
        IDelegationManager,
        IStrategyManager,
        IStrategy
    );

    function setEigenlayerContracts(
        IDelegationManager _delegationManager,
        IStrategyManager _strategyManager,
        IStrategy _strategy
    ) external;

    function setQueueWithdrawalBlock(address staker, uint256 nonce) external;

    function getQueueWithdrawalBlock(address staker, uint256 nonce) external returns (uint256);

    function decodeFunctionSelector(bytes memory message) external returns (bytes4);

    function setFunctionSelectorName(
        bytes4 functionSelector,
        string memory _name
    ) external returns (string memory);

    function getFunctionSelectorName(bytes4 functionSelector) external returns (string memory);

    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) external;

    function getGasLimitForFunctionSelector(bytes4 functionSelector) external returns (uint256);
}