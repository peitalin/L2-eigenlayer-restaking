// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

import {EigenlayerMsgDecoders} from "./utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "./utils/EigenlayerMsgEncoders.sol";
import {Adminable} from "./utils/Adminable.sol";

import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";



contract RestakingConnector is
    Initializable,
    IRestakingConnector,
    EigenlayerMsgDecoders,
    Adminable
{

    IDelegationManager public delegationManager;
    IStrategyManager public strategyManager;
    IStrategy public strategy;

    address private _receiverCCIP;
    IAgentFactory public agentFactory;

    error AddressZero(string msg);

    event SetQueueWithdrawalBlock(address indexed, uint256 indexed, uint256 indexed);
    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);

    mapping(address user => mapping(uint256 nonce => uint256 withdrawalBlock)) private _withdrawalBlock;
    mapping(bytes4 => uint256) internal _gasLimitsForFunctionSelectors;

    /*
     *
     *                 Functions
     *
     *
     */

    constructor() {
        _disableInitializers();
    }

    function initialize(IAgentFactory newAgentFactory) initializer public {

        if (address(newAgentFactory) == address(0))
            revert AddressZero("AgentFactory cannot be address(0)");

        agentFactory = newAgentFactory;

        // handleTransferToAgentOwner: [gas: 268_420]
        // cast sig "handleTransferToAgentOwner(bytes32,address,bytes32)" == 0x17f23aea
        _gasLimitsForFunctionSelectors[0x17f23aea] = 400_000;

        __Adminable_init();
    }

    modifier onlyReceiverCCIP() {
        require(msg.sender == _receiverCCIP, "not called by ReceiverCCIP");
        _;
    }

    function getReceiverCCIP() public view returns (address) {
        return _receiverCCIP;
    }

    function setReceiverCCIP(address newReceiverCCIP) public onlyOwner {
        _receiverCCIP = newReceiverCCIP;
    }

    function getAgentFactory() public view returns (address) {
        return address(agentFactory);
    }

    function setAgentFactory(address newAgentFactory) public onlyOwner {
        if (newAgentFactory == address(0))
            revert AddressZero("AgentFactory cannot be address(0)");

        agentFactory = IAgentFactory(newAgentFactory);
    }

    /*
     *
     *                EigenAgent <> Eigenlayer Handlers
     *
     *
    */

    function depositWithEigenAgent(bytes memory messageWithSignature) public onlyReceiverCCIP {

        (
            // original message
            address _strategy,
            address token,
            uint256 amount,
            // message signature
            address signer, // original_staker
            uint256 expiry,
            bytes memory signature // signature from original_staker
        ) = decodeDepositWithSignature6551Msg(messageWithSignature);

        // get original_staker's EigenAgent, or spawn one.
        IEigenAgent6551 eigenAgent = agentFactory.tryGetEigenAgentOrSpawn(signer);

        bytes memory depositData = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
            _strategy,
            token,
            amount
        );

        // Note I: Token flow:
        // ReceiverCCIP approves RestakingConnector to move tokens to EigenAgent,
        // then EigenAgent approves StrategyManager to move tokens into Eigenlayer
        eigenAgent.approveByWhitelistedContract(
            address(strategyManager), // strategyManager
            token,
            amount
        );

        // ReceiverCCIP approves RestakingConnector just before calling this function
        IERC20(token).transferFrom(
            _receiverCCIP,
            address(eigenAgent),
            amount
        );

        eigenAgent.executeWithSignature(
            address(strategyManager), // strategyManager
            0 ether,
            depositData, // encodeDepositIntoStrategyMsg
            expiry,
            signature
        );
    }

    function queueWithdrawalsWithEigenAgent(bytes memory messageWithSignature) public onlyReceiverCCIP {

        (
            // original message
            IDelegationManager.QueuedWithdrawalParams[] memory QWPArray,
            // message signature
            address signer,
            uint256 expiry,
            bytes memory signature
        ) = decodeQueueWithdrawalsMsg(messageWithSignature);

        address withdrawer = QWPArray[0].withdrawer;
        /// @note: DelegationManager.queueWithdrawals requires:
        /// msg.sender == withdrawer == staker (EigenAgent is all three)
        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(withdrawer));

        uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(withdrawer);

        _withdrawalBlock[withdrawer][withdrawalNonce] = block.number;

        bytes memory result = eigenAgent.executeWithSignature(
            address(delegationManager),
            0 ether,
            EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(QWPArray),
            expiry,
            signature
        );
    }

    function completeWithdrawalWithEigenAgent(bytes memory messageWithSignature)
        public onlyReceiverCCIP
        returns (
            uint256 withdrawalAmount,
            address withdrawalToken,
            string memory messageForL2
        )
    {

        (
            // original message
            IDelegationManager.Withdrawal memory withdrawal,
            IERC20[] memory tokensToWithdraw,
            uint256 middlewareTimesIndex,
            bool receiveAsTokens,
            // message signature
            address signer,
            uint256 expiry,
            bytes memory signature
        ) = decodeCompleteWithdrawalMsg(messageWithSignature);

        // eigenAgent == withdrawer == staker == msg.sender (in Eigenlayer)
        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(withdrawal.withdrawer));

        // (1) EigenAgent receives tokens from Eigenlayer
        // then (2) approves RestakingConnector to (3) transfer tokens to ReceiverCCIP
        eigenAgent.executeWithSignature(
            address(delegationManager),
            0 ether,
            EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                middlewareTimesIndex,
                receiveAsTokens
            ),
            expiry,
            signature
        );

        // DelegationManager requires(msg.sender == withdrawal.withdrawer), only EigenAgent can withdraw.
        bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);

        withdrawalAmount = withdrawal.shares[0];
        withdrawalToken = address(tokensToWithdraw[0]);
        messageForL2 = string(encodeHandleTransferToAgentOwnerMsg(
            withdrawalRoot,
            signer // signer should be eigenAgent.getAgentOwner()
        ));

        // (2) EigenAgent approves RestakingConnector to transfer tokens to ReceiverCCIP
        eigenAgent.approveByWhitelistedContract(
            address(this), // restakingConnector
            withdrawalToken,
            withdrawalAmount
        );
        // (3) RestakingConnector transfers tokens to ReceiverCCIP, to bridge tokens to Router (bridge)
        IERC20(withdrawalToken).transferFrom(
            address(eigenAgent),
            _receiverCCIP,
            withdrawalAmount
        );

        return (
            withdrawalAmount,
            address(withdrawalToken),
            messageForL2
        );
    }

    function delegateToWithEigenAgent(bytes memory messageWithSignature) public onlyReceiverCCIP {
        (
            // original message
            address staker,
            address operator,
            ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry,
            ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
            bytes32 approverSalt
            // // message signature
            // address signer,
            // uint256 expiry,
            // bytes memory signature
        ) = decodeDelegateToBySignatureMsg(messageWithSignature);

        delegationManager.delegateToBySignature(
            staker,
            operator,
            stakerSignatureAndExpiry,
            approverSignatureAndExpiry,
            approverSalt
        );
    }

    /*
     *
     *                 Functions
     *
     *
    */

    function encodeHandleTransferToAgentOwnerMsg(
        bytes32 withdrawalRoot,
        address agentOwner
    ) public pure returns (bytes memory) {
        return EigenlayerMsgEncoders.encodeHandleTransferToAgentOwnerMsg(withdrawalRoot, agentOwner);
    }

    function getQueueWithdrawalBlock(address staker, uint256 nonce) public view returns (uint256) {
        return _withdrawalBlock[staker][nonce];
    }

    /// @dev Checkpoint the actual block.number before queueWithdrawal happens
    /// When dispatching a L2 -> L1 message to queueWithdrawal, the block.number
    /// varies depending on how long it takes to bridge.
    /// We need the block.number to in the following step to
    /// create the withdrawalRoot used to completeWithdrawal.
    function setQueueWithdrawalBlock(
        address staker,
        uint256 nonce,
        uint256 blockNumber
    ) external onlyAdminOrOwner {
        _withdrawalBlock[staker][nonce] = blockNumber;
        emit SetQueueWithdrawalBlock(staker, nonce, blockNumber);
    }

    function getEigenlayerContracts()
        public view
        returns (IDelegationManager, IStrategyManager, IStrategy)
    {
        return (delegationManager, strategyManager, strategy);
    }

    function setEigenlayerContracts(
        IDelegationManager _delegationManager,
        IStrategyManager _strategyManager,
        IStrategy _strategy
    ) public onlyOwner {

        if (address(_delegationManager) == address(0))
            revert AddressZero("_delegationManager cannot be address(0)");

        if (address(_strategyManager) == address(0))
            revert AddressZero("_strategyManager cannot be address(0)");

        if (address(_strategy) == address(0))
            revert AddressZero("_strategy cannot be address(0)");

        delegationManager = _delegationManager;
        strategyManager = _strategyManager;
        strategy = _strategy;
    }

    function setGasLimitsForFunctionSelectors(
        bytes4[] memory functionSelectors,
        uint256[] memory gasLimits
    ) public onlyAdminOrOwner {

        require(functionSelectors.length == gasLimits.length, "input arrays must have the same length");

        for (uint256 i = 0; i < gasLimits.length; ++i) {
            _gasLimitsForFunctionSelectors[functionSelectors[i]] = gasLimits[i];
            emit SetGasLimitForFunctionSelector(functionSelectors[i], gasLimits[i]);
        }
    }

    function getGasLimitForFunctionSelector(bytes4 functionSelector) public view returns (uint256) {
        uint256 gasLimit = _gasLimitsForFunctionSelectors[functionSelector];
        if (gasLimit != 0) {
            return gasLimit;
        } else {
            // default gasLimit
            return 400_000;
        }
    }
}