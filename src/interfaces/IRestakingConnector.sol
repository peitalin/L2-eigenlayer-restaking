// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgent6551} from "../../src/6551/IEigenAgent6551.sol";
import {IEigenAgentOwner721} from "../../src/6551/IEigenAgentOwner721.sol";


interface IRestakingConnector {

    function getReceiverCCIP() external view returns (address);

    function setReceiverCCIP(address newReceiverCCIP) external;

    /*
     *
     *                EigenAgent -> Eigenlayer Handlers
     *
     *
    */

    function getAgentFactory() external view returns (address);

    function setAgentFactory(address newAgentFactory) external;

    function depositWithEigenAgent(bytes memory message) external;

    function queueWithdrawalsWithEigenAgent(bytes memory message) external;

    function completeWithdrawalWithEigenAgent(bytes memory message) external returns (
        uint256,
        address,
        string memory // CCIP message for transferToAgentOwner on L2
    );

    function delegateToWithEigenAgent(bytes memory message) external;

    function undelegateWithEigenAgent(bytes memory message) external;

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

    function getQueueWithdrawalBlock(address staker, uint256 nonce) external returns (uint256);

    function setQueueWithdrawalBlock(address staker, uint256 nonce, uint256 blockNumber) external;

    /*
     *
     *              Messaging Helpers
     *
     *
    */

    function encodeHandleTransferToAgentOwnerMsg(
        bytes32 withdrawalRoot,
        address agentOwner
    ) external returns (bytes memory);

    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) external;

    function getGasLimitForFunctionSelector(
        bytes4 functionSelector
    ) external returns (uint256);

}