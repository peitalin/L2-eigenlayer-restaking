// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {Adminable} from "./utils/Adminable.sol";
import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {EigenlayerMsgDecoders} from "./utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "./utils/EigenlayerMsgEncoders.sol";
import {FunctionSelectorDecoder} from "./FunctionSelectorDecoder.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

import {EigenlayerDeposit6551Msg} from "./interfaces/IEigenlayerMsgDecoders.sol";
import {ERC6551AccountProxy} from "@6551/examples/upgradeable/ERC6551AccountProxy.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";



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

    error AddressNull();
    error InvalidContractAddress(string msg);

    event SetQueueWithdrawalBlock(address indexed, uint256 indexed, uint256 indexed);
    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);

    mapping(address user => mapping(uint256 nonce => uint256 withdrawalBlock)) private _withdrawalBlock;

    mapping(bytes4 => uint256) internal _gasLimitsForFunctionSelectors;
    mapping(bytes4 => string) internal _functionSelectorNames;

    IERC6551Registry public erc6551Registry;
    EigenAgentOwner721 public eigenAgentOwner721;

    mapping(address => uint256) public userToEigenAgentTokenIds;
    mapping(uint256 => address) public tokenIdToEigenAgents;

    event EigenAgentOwnerUpdated(address indexed, address indexed, uint256 indexed);

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
        EigenAgentOwner721 _eigenAgentOwner721
    ) initializer public {

        if (address(_erc6551Registry) == address(0))
            revert InvalidContractAddress("ERC6551Registry cannot be address(0)");

        if (address(_eigenAgentOwner721) == address(0))
            revert InvalidContractAddress("EigenAgentOwner721 cannot be address(0)");

        erc6551Registry = _erc6551Registry;
        eigenAgentOwner721 = _eigenAgentOwner721;

        __Adminable_init();

        // handleTransferToAgentOwner: [gas: 268_420]
        // bytes4(keccak256("handleTransferToAgentOwner(bytes32,address,bytes32)")) == 0x17f23aea
        _gasLimitsForFunctionSelectors[0x17f23aea] = 400_000;
        _functionSelectorNames[0x17f23aea] = "handleTransferToAgentOwner";

    }

    modifier onlyReceiverCCIP() {
        require(msg.sender == _receiverCCIP, "not called by ReceiverCCIP");
        _;
    }

    /*
     *
     *                 EigenAgent
     *
     *
    */

    function get6551Registry() public view returns (IERC6551Registry) {
        return erc6551Registry;
    }

    function getEigenAgentOwner721() public view returns (EigenAgentOwner721) {
        return eigenAgentOwner721;
    }

    function getReceiverCCIP() public view returns (address) {
        return _receiverCCIP;
    }

    function setReceiverCCIP(address newReceiverCCIP) public onlyOwner {
        _receiverCCIP = newReceiverCCIP;
    }

    function updateEigenAgentOwnerTokenId(
        address from,
        address to,
        uint256 tokenId
    ) external returns (uint256) {
        require(
            msg.sender == address(eigenAgentOwner721),
            "ReceiverCCIP.updateEigenAgentOwnerTokenId: only EigenAgentOwner721 can update"
        );
        userToEigenAgentTokenIds[from] = 0;
        userToEigenAgentTokenIds[to] = tokenId;
        emit EigenAgentOwnerUpdated(from, to, tokenId);
    }

    function getEigenAgentOwnerTokenId(address staker) public view returns (uint256) {
        return userToEigenAgentTokenIds[staker];
    }

    function getEigenAgent(address staker) public view returns (address) {
        return tokenIdToEigenAgents[userToEigenAgentTokenIds[staker]];
    }

    function spawnEigenAgentOnlyOwner(address staker) external onlyOwner returns (IEigenAgent6551) {
        return _spawnEigenAgent6551(staker);
    }

    function _tryGetEigenAgentOrSpawn(address staker) internal returns (IEigenAgent6551) {
        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(getEigenAgent(staker)));
        if (address(eigenAgent) == address(0)) {
            return _spawnEigenAgent6551(staker);
        }
        return eigenAgent;
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

    /*
     *
     *                EigenAgent <> Eigenlayer Handlers
     *
     *
    */

    function depositWithEigenAgent(
        bytes memory message,
        address token,
        uint256 amount
    ) public onlyReceiverCCIP {

        EigenlayerDeposit6551Msg memory eigenMsg = decodeDepositWithSignature6551Msg(message);
        IEigenAgent6551 eigenAgent = _tryGetEigenAgentOrSpawn(eigenMsg.staker);

        bytes memory depositData = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
            address(strategy),
            token,
            eigenMsg.amount
        );

        // Note: eigenAgent approves() StrategyManager using DepositIntoStrategy signature
        // which signs over (from, to, amount, strategy) fields.
        // see: encodeDepositWithSignature6551Msg
        eigenAgent.approveStrategyManagerWithSignature(
            address(strategyManager), // strategyManager
            0 ether,
            depositData,
            eigenMsg.expiry,
            eigenMsg.signature
        );

        IERC20(token).transfer(address(eigenAgent), eigenMsg.amount);

        bytes memory result = eigenAgent.executeWithSignature(
            address(strategyManager), // strategyManager
            0 ether,
            depositData, // encodeDepositIntoStrategyMsg
            eigenMsg.expiry,
            eigenMsg.signature
        );
    }

    function queueWithdrawalsWithEigenAgent(
        bytes memory message,
        address token,
        uint256 amount
    ) public onlyReceiverCCIP {

        (
            IDelegationManager.QueuedWithdrawalParams[] memory QWPArray,
            uint256 expiry,
            bytes memory signature
        ) = decodeQueueWithdrawalsMsg(message);

        /// @note: DelegationManager.queueWithdrawals requires:
        /// msg.sender == withdrawer == staker
        /// EigenAgent is all three.
        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(QWPArray[0].withdrawer));

        bytes memory result = eigenAgent.executeWithSignature(
            address(delegationManager),
            0 ether,
            EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(QWPArray),
            expiry,
            signature
        );
    }

    function completeWithdrawalWithEigenAgent(
        bytes memory message,
        address token,
        uint256 amount
    ) public onlyReceiverCCIP returns (
        IDelegationManager.Withdrawal memory,
        string memory
    ) {

        (
            IDelegationManager.Withdrawal memory withdrawal,
            IERC20[] memory tokensToWithdraw,
            uint256 middlewareTimesIndex,
            bool receiveAsTokens,
            uint256 expiry,
            bytes memory signature
        ) = decodeCompleteWithdrawalMsg(message);

        // eigenAgent == withdrawer == staker == msg.sender (in Eigenlayer)
        IEigenAgent6551 eigenAgent = IEigenAgent6551(payable(withdrawal.withdrawer));
        address agentOwner = eigenAgent.getAgentOwner();

        bytes memory result = eigenAgent.executeWithSignature(
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

        // DelegationManager requires(msg.sender == withdrawal.withdrawer), so only EigenAgent can withdraw.
        // then it calculates withdrawalRoot ensuring staker/withdrawal/block is a valid withdrawal.
        bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);

        // address original_staker = withdrawal.staker;
        uint256 amount = withdrawal.shares[0];
        // Approve L1 receiverContract to send ccip-BnM tokens to Router
        IERC20 token = withdrawal.strategies[0].underlyingToken();
        token.approve(address(this), amount);

        string memory messageForL2 = string(encodeHandleTransferToAgentOwnerMsg(
            withdrawalRoot,
            agentOwner
        ));

        return (
            withdrawal,
            messageForL2
        );
    }

    function delegateToWithEigenAgent(
        bytes memory message,
        address token,
        uint256 amount
    ) public onlyReceiverCCIP {
        (
            address staker,
            address operator,
            ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry,
            ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
            bytes32 approverSalt
        ) = decodeDelegateToBySignatureMsg(message);

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

    function decodeFunctionSelector(bytes memory message) public returns (bytes4) {
        return FunctionSelectorDecoder.decodeFunctionSelector(message);
    }

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
    function setQueueWithdrawalBlock(address staker, uint256 nonce) external onlyAdminOrOwner {
        _withdrawalBlock[staker][nonce] = block.number;
        emit SetQueueWithdrawalBlock(staker, nonce, block.number);
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

        if (address(_delegationManager) == address(0)) revert AddressNull();
        if (address(_strategyManager) == address(0)) revert AddressNull();
        if (address(_strategy) == address(0)) revert AddressNull();

        delegationManager = _delegationManager;
        strategyManager = _strategyManager;
        strategy = _strategy;
    }

    function setFunctionSelectorName(
        bytes4 functionSelector,
        string memory _name
    ) public onlyAdminOrOwner returns (string memory) {
        return _functionSelectorNames[functionSelector] = _name;
    }

    function getFunctionSelectorName(bytes4 functionSelector) public view returns (string memory) {
        return _functionSelectorNames[functionSelector];
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