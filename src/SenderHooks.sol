// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin-v5-contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin-v47-contracts/token/ERC20/IERC20.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {ISenderHooks} from "./interfaces/ISenderHooks.sol";
import {EigenlayerMsgDecoders, TransferToAgentOwnerMsg} from "./utils/EigenlayerMsgDecoders.sol";
import {FunctionSelectorDecoder} from "./utils/FunctionSelectorDecoder.sol";
import {Adminable} from "./utils/Adminable.sol";


/// @title Sender Hooks: processes SenderCCIP messages and stores state
contract SenderHooks is Initializable, Adminable, EigenlayerMsgDecoders {


    mapping(bytes4 => uint256) internal _gasLimitsForFunctionSelectors;

    address internal _senderCCIP;

    /// @notice lookup L2 token addresses of bridgeable tokens
    mapping(address bridgeTokenL1 => address bridgeTokenL2) public bridgeTokensL1toL2;

    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);

    event SetSenderCCIP(address indexed);
    event SetBridgeTokens(address indexed, address indexed);
    event ClearBridgeTokens(address indexed);

    error AddressZero(string msg);
    error OnlySendFundsForDeposits(bytes4 functionSelector, string msg);
    error OnlyDepositOneTokenAtATime(string msg);
    error UnsupportedFunctionCall(bytes4 functionSelector);

    constructor() {
        _disableInitializers();
    }

    /// @param _bridgeTokenL1 address of the bridging token's L1 contract.
    /// @param _bridgeTokenL2 address of the bridging token's L2 contract.
    function initialize(address _bridgeTokenL1, address _bridgeTokenL2) external initializer {

        if (_bridgeTokenL1 == address(0))
            revert AddressZero("_bridgeTokenL1 cannot be address(0)");

        if (_bridgeTokenL2 == address(0))
            revert AddressZero("_bridgeTokenL2 cannot be address(0)");

        bridgeTokensL1toL2[_bridgeTokenL1] = _bridgeTokenL2;

        __Adminable_init();
    }

    modifier onlySenderCCIP() {
        require(msg.sender == _senderCCIP, "not called by SenderCCIP");
        _;
    }

    function getSenderCCIP() external view returns (address) {
        return _senderCCIP;
    }

    /// @param newSenderCCIP address of the SenderCCIP contract.
    function setSenderCCIP(address newSenderCCIP) external onlyOwner {
        if (newSenderCCIP == address(0))
            revert AddressZero("SenderCCIP cannot be address(0)");

        _senderCCIP = newSenderCCIP;
        emit SetSenderCCIP(newSenderCCIP);
    }

    /**
     * @dev Retrieves estimated gasLimits for different L2 restaking functions, e.g:
     * - depositIntoStrategy(address,address,uint256) == 0xe7a050aa
     * - mintEigenAgent(bytes) == 0xcc15a557
     * - queueWithdrawals((address[],uint256[],address)[]) == 0x0dd8dd02
     * - completeQueuedWithdrawal(withdrawal,address[],bool) == 0xe4cc3f90
     * - delegateTo(address,(bytes,uint256),bytes32) == 0xeea9064b
     * - undelegate(address) == 0xda8be864
     * @param functionSelector bytes4 functionSelector to get estimated gasLimits for.
     * @return gasLimit if functionSelector is supported, otherwise reverts.
     */
    function getGasLimitForFunctionSelector(bytes4 functionSelector)
        public
        view
        returns (uint256)
    {
        uint256 gasLimit = _gasLimitsForFunctionSelectors[functionSelector];
        if (gasLimit == 0) {
            revert UnsupportedFunctionCall(functionSelector);
        }
        return gasLimit;
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
    ) external onlyOwner {
        require(functionSelectors.length == gasLimits.length, "input arrays must have the same length");
        for (uint256 i = 0; i < gasLimits.length; ++i) {
            _gasLimitsForFunctionSelectors[functionSelectors[i]] = gasLimits[i];
            emit SetGasLimitForFunctionSelector(functionSelectors[i], gasLimits[i]);
        }
    }

    /**
     * @notice outlines which token pairs are bridgeable, and their L1 and L2 addresses
     * @param _bridgeTokenL1 bridging token's address on L1
     * @param _bridgeTokenL2 bridging token's address on L2
     */
    function setBridgeTokens(address _bridgeTokenL1, address _bridgeTokenL2) external onlyOwner {

        if (_bridgeTokenL1 == address(0))
            revert AddressZero("_bridgeTokenL1 cannot be address(0)");

        if (_bridgeTokenL2 == address(0))
            revert AddressZero("_bridgeTokenL2 cannot be address(0)");

        bridgeTokensL1toL2[_bridgeTokenL1] = _bridgeTokenL2;
        emit SetBridgeTokens(_bridgeTokenL1, _bridgeTokenL2);
    }

    /**
     * @notice clears a token pair
     * @param _bridgeTokenL1 bridging token's address on L1
     */
    function clearBridgeTokens(address _bridgeTokenL1) external onlyOwner {
        delete bridgeTokensL1toL2[_bridgeTokenL1];
        emit ClearBridgeTokens(_bridgeTokenL1);
    }

    /*
     *
     *                L2 Withdrawal Transfers / Rewards Transfers
     *
     *
    */

    /**
     * @dev This function handles inbound L1 -> L2 completeWithdrawal messages after Eigenlayer has
     * withdrawn funds, and the L1 bridge has bridged them back to L2. It decodes the AgentOwner to
     * transfer the withdrawn funds to on L2
     * Only callable from SenderCCIP.
     */
    function handleTransferToAgentOwner(bytes memory message)
        external
        view
        onlySenderCCIP
        returns (address agentOwner)
    {
        TransferToAgentOwnerMsg memory transferToAgentOwnerMsg = decodeTransferToAgentOwnerMsg(message);
        return transferToAgentOwnerMsg.agentOwner;
    }

    /**
     * @dev Hook that executes in outbound sendMessagePayNative calls. Used for validation.
     * @param message is the outbound message passed to CCIP's _buildCCIPMessage function
     * @param tokenAmounts is the amounts of tokens being sent
     */
    function beforeSendCCIPMessage(
        bytes memory message,
        Client.EVMTokenAmount[] memory tokenAmounts
    ) external view onlySenderCCIP returns (uint256 gasLimit) {

        bytes4 functionSelector = FunctionSelectorDecoder.decodeFunctionSelector(message);
        gasLimit = getGasLimitForFunctionSelector(functionSelector);

        if (tokenAmounts.length > 1) {
            revert OnlyDepositOneTokenAtATime("Eigenlayer only deposits one token at a time");
        }
        if (
            tokenAmounts.length > 0 &&
            functionSelector != IStrategyManager.depositIntoStrategy.selector
        ) {
            // check tokens are only bridged for deposit calls
            if (tokenAmounts[0].amount > 0) {
                revert OnlySendFundsForDeposits(functionSelector,"Only send funds for DepositIntoStrategy calls");
            }
        }

        return gasLimit;
    }
}

