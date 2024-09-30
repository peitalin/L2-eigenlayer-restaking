// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {Adminable} from "./utils/Adminable.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";



abstract contract RestakingConnectorStorage is Adminable, IRestakingConnector {

    IDelegationManager public delegationManager;
    IStrategyManager public strategyManager;
    IStrategy public strategy;
    IRewardsCoordinator public rewardsCoordinator;

    IAgentFactory public agentFactory;
    address internal _receiverCCIP;

    /// @notice lookup L2 token addresses of bridgeable tokens
    mapping(address bridgeTokenL1 => address bridgeTokenL2) public bridgeTokensL1toL2;

    /// @notice set withdrawalBlock to mark when a queuedWithdrawal occurred
    mapping(address user => mapping(uint256 nonce => uint256 withdrawalBlock)) _withdrawalBlock;

    mapping(bytes4 => uint256) internal _gasLimitsForFunctionSelectors;

    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);

    error AddressZero(string reason);
    error TooManyTokensToDeposit(string reason);

    /*
     *
     *                 Functions
     *
     *
     */

    constructor() {
        _disableInitializers();
    }

    /// @param _agentFactory address of the bridging token's L1 contract.
    /// @param _bridgeTokenL1 address of the bridging token's L1 contract.
    /// @param _bridgeTokenL2 address of the bridging token's L2 contract.
    function __RestakingConnectorStorage_init(
        IAgentFactory _agentFactory,
        address _bridgeTokenL1,
        address _bridgeTokenL2
    ) internal {

        if (address(_agentFactory) == address(0))
            revert AddressZero("AgentFactory cannot be address(0)");

        if (_bridgeTokenL1 == address(0))
            revert AddressZero("_bridgeTokenL1 cannot be address(0)");

        if (_bridgeTokenL2 == address(0))
            revert AddressZero("_bridgeTokenL2 cannot be address(0)");

        agentFactory = _agentFactory;
        bridgeTokensL1toL2[_bridgeTokenL1] = _bridgeTokenL2;

        __Adminable_init();
    }

    modifier onlyReceiverCCIP() {
        require(msg.sender == _receiverCCIP, "not called by ReceiverCCIP");
        _;
    }

    function getReceiverCCIP() external view returns (address) {
        return _receiverCCIP;
    }

    /// @param newReceiverCCIP address of the ReceiverCCIP contract.
    function setReceiverCCIP(address newReceiverCCIP) external onlyOwner {
        _receiverCCIP = newReceiverCCIP;
    }

    function getAgentFactory() external view returns (address) {
        return address(agentFactory);
    }

    /// @param newAgentFactory address of the AgentFactory contract.
    function setAgentFactory(address newAgentFactory) external onlyOwner {
        if (newAgentFactory == address(0))
            revert AddressZero("AgentFactory cannot be address(0)");

        agentFactory = IAgentFactory(newAgentFactory);
    }

    function getEigenlayerContracts() external view returns (
        IDelegationManager,
        IStrategyManager,
        IStrategy,
        IRewardsCoordinator
    ) {
        return (delegationManager, strategyManager, strategy, rewardsCoordinator);
    }

    function setEigenlayerContracts(
        IDelegationManager _delegationManager,
        IStrategyManager _strategyManager,
        IStrategy _strategy,
        IRewardsCoordinator _rewardsCoordinator
    ) external onlyOwner {

        if (address(_delegationManager) == address(0))
            revert AddressZero("_delegationManager cannot be address(0)");

        if (address(_strategyManager) == address(0))
            revert AddressZero("_strategyManager cannot be address(0)");

        if (address(_strategy) == address(0))
            revert AddressZero("_strategy cannot be address(0)");

        if (address(_rewardsCoordinator) == address(0))
            revert AddressZero("_rewardsCoordinator cannot be address(0)");

        delegationManager = _delegationManager;
        strategyManager = _strategyManager;
        strategy = _strategy;
        rewardsCoordinator = _rewardsCoordinator;
    }

    /**
     * @notice mark a L1/L2 token pair as bridgeable, for withdrawals and rewards claiming
     * @param _bridgeTokenL1 bridging token's address on L1
     * @param _bridgeTokenL2 bridging token's address on L2
     */
    function setBridgeTokens(address _bridgeTokenL1, address _bridgeTokenL2) external onlyOwner {

        if (_bridgeTokenL1 == address(0))
            revert AddressZero("_bridgeTokenL1 cannot be address(0)");

        if (_bridgeTokenL2 == address(0))
            revert AddressZero("_bridgeTokenL2 cannot be address(0)");

        bridgeTokensL1toL2[_bridgeTokenL1] = _bridgeTokenL2;
    }

    /**
     * @notice clears a token pair
     * @param _bridgeTokenL1 bridging token's address on L1
     */
    function clearBridgeTokens(address _bridgeTokenL1) external onlyOwner {
        delete bridgeTokensL1toL2[_bridgeTokenL1];
    }

    /**
     * @dev Retrieves estimated gasLimits for different L2 restaking functions, e.g:
     * "handleTransferToAgentOwner(bytes)" == 0xd8a85b48
     * @param functionSelector bytes4 functionSelector to get estimated gasLimits for.
     * @return gasLimit a default gasLimit of 200_000 functionSelector parameter finds no matches.
     */
    function getGasLimitForFunctionSelector(bytes4 functionSelector)
        external
        view
        returns (uint256)
    {
        uint256 gasLimit = _gasLimitsForFunctionSelectors[functionSelector];
        return (gasLimit > 0) ? gasLimit : 200_000;
    }

    /**
     * @dev Sets gas limits for various functions. Requires an array of bytes4 function selectors and
     * a corresponding array of gas limits.
     * @param functionSelectors list of bytes4 function selectors
     * @param gasLimits list of gasLimits to set the gasLimits for functions to call
     */
    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) external onlyAdminOrOwner {

        require(functionSelectors.length == gasLimits.length, "input arrays must have the same length");

        for (uint256 i = 0; i < gasLimits.length; ++i) {
            _gasLimitsForFunctionSelectors[functionSelectors[i]] = gasLimits[i];
            emit SetGasLimitForFunctionSelector(functionSelectors[i], gasLimits[i]);
        }
    }

    function dispatchMessageToEigenAgent(Client.Any2EVMMessage memory any2EvmMessage)
        external
        virtual
        returns (TransferTokensInfo[] memory);

    function mintEigenAgent(bytes memory message) external virtual;
}