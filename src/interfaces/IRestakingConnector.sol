// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Client} from "@chainlink/ccip/libraries/Client.sol";
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

    function bridgeTokensL1toL2(address _bridgeTokenL1) external returns (address);

    function setBridgeTokens(address _bridgeTokenL1, address _bridgeTokenL2) external;

    function clearBridgeTokens(address _bridgeTokenL1) external;

    /*
     *
     *           EigenAgent -> Eigenlayer Handlers
     *
     *
    */

    enum TransferType {
        Withdrawal,
        RewardsClaim
    }

    struct TransferTokensInfo {
        TransferType transferType;
        string transferToAgentOwnerMessage;
        bytes32 transferRoot;
        address transferToken;
        uint256 transferAmount;
    }

    function dispatchMessageToEigenAgent(Client.Any2EVMMessage memory any2EvmMessage)
        external
        returns (TransferTokensInfo[] memory);

    function mintEigenAgent(bytes memory message) external;
}