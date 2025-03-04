// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin-v47-contracts/token/ERC20/IERC20.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {Adminable} from "./utils/Adminable.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";



abstract contract RestakingConnectorStorage is Adminable, IRestakingConnector {

    IDelegationManager internal delegationManager;
    IStrategyManager internal strategyManager;
    IStrategy internal strategy;
    IRewardsCoordinator internal rewardsCoordinator;

    IAgentFactory internal agentFactory;
    address internal _receiverCCIP;

    /// @notice lookup L2 token addresses of bridgeable tokens
    mapping(address bridgeTokenL1 => address bridgeTokenL2) public bridgeTokensL1toL2;

    /// @notice set withdrawalBlock to mark when a queuedWithdrawal occurred
    mapping(address user => mapping(uint256 nonce => uint256 withdrawalBlock)) _withdrawalBlock;

    mapping(bytes4 => uint256) internal _gasLimitsForFunctionSelectors;

    event SetGasLimitForFunctionSelector(bytes4, uint256);

    // When adding custom errors, update decodeEigenAgentExecutionError
    // to decode the new error selector and display error messages properly.
    error AddressZero();
    error TooManyTokensToDeposit();
    error TokenAmountMismatch();

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
            revert AddressZero();

        if (_bridgeTokenL1 == address(0))
            revert AddressZero();

        if (_bridgeTokenL2 == address(0))
            revert AddressZero();

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
            revert AddressZero();

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
            revert AddressZero();

        if (address(_strategyManager) == address(0))
            revert AddressZero();

        if (address(_strategy) == address(0))
            revert AddressZero();

        if (address(_rewardsCoordinator) == address(0))
            revert AddressZero();

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
            revert AddressZero();

        if (_bridgeTokenL2 == address(0))
            revert AddressZero();

        bridgeTokensL1toL2[_bridgeTokenL1] = _bridgeTokenL2;
    }

    /**
     * @dev Retrieves estimated gasLimits for different L2 restaking functions, e.g:
     * "handleTransferToAgentOwner(bytes)" == 0xd8a85b48
     * @param functionSelector bytes4 functionSelector to get estimated gasLimits for.
     * @return gasLimit a default gasLimit of 200_000 functionSelector parame
ter finds no matches.
     */
    function getGasLimitForFunctionSelectorL1(bytes4 functionSelector)
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
        returns (TransferTokensInfo memory);

    function mintEigenAgent(bytes memory message) external virtual;
}