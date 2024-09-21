// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";


interface IRestakingConnector {

    error EigenAgentExecutionError(address signer, uint256 expiry, bytes err);

    error EigenAgentExecutionErrorStr(address signer, uint256 expiry, string err);

    error ExecutionErrorRefundAfterExpiry(string err, string refundMessage, uint256 expiry);

    function getReceiverCCIP() external view returns (address);

    function setReceiverCCIP(address newReceiverCCIP) external;

    function getAgentFactory() external view returns (address);

    function setAgentFactory(address newAgentFactory) external;

    function getEigenlayerContracts() external returns (
        IDelegationManager,
        IStrategyManager,
        IStrategy,
        IRewardsCoordinator
    );

    function setEigenlayerContracts(
        IDelegationManager _delegationManager,
        IStrategyManager _strategyManager,
        IStrategy _strategy,
        IRewardsCoordinator _rewardsCoordinator
    ) external;

    function getGasLimitForFunctionSelector(bytes4 functionSelector) external returns (uint256);

    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) external;

    function getQueueWithdrawalBlock(address staker, uint256 nonce) external returns (uint256);

    function setQueueWithdrawalBlock(address staker, uint256 nonce, uint256 blockNumber) external;

    /*
     *
     *           EigenAgent -> Eigenlayer Handlers
     *
     *
    */

    function depositWithEigenAgent(bytes memory message) external;

    function mintEigenAgent(bytes memory message) external;

    function queueWithdrawalsWithEigenAgent(bytes memory message) external;

    function completeWithdrawalWithEigenAgent(bytes memory message) external returns (
        bool receiveAsTokens,
        string memory messageForL2, // CCIP message: transferToAgentOwner on L2
        bytes32 withdrawalTransferRoot,
        address withdrawalToken,
        uint256 withdrawalAmount
    );

    function delegateToWithEigenAgent(bytes memory message) external;

    function undelegateWithEigenAgent(bytes memory message) external;

    function processClaimWithEigenAgent(bytes memory message) external returns (
        string memory messageForL2,
        bytes32 rewardsTransferRoot,
        address rewardsToken,
        uint256 rewardsAmount
    );

}