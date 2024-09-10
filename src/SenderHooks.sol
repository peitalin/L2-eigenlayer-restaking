// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {Adminable} from "./utils/Adminable.sol";

import {ISenderHooks} from "./interfaces/ISenderHooks.sol";
import {EigenlayerMsgDecoders, TransferToAgentOwnerMsg} from "./utils/EigenlayerMsgDecoders.sol";
import {FunctionSelectorDecoder} from "./utils/FunctionSelectorDecoder.sol";


/// @title Sender Hooks: processes SenderCCIP messages and stores state
contract SenderHooks is Initializable, Adminable, EigenlayerMsgDecoders {

    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);
    event SendingWithdrawalToAgentOwner(address indexed, uint256 indexed);
    event WithdrawalTransferRootCommitted(
        bytes32 indexed, // withdrawalTransferRoot
        address indexed, //  withdrawer (eigenAgent)
        uint256, // amount
        address  // signer (agentOwner)
    );

    error AddressZero(string msg);

    mapping(bytes32 => ISenderHooks.WithdrawalTransfer) public withdrawalTransferCommitments;
    mapping(bytes32 => bool) public withdrawalTransferRootsSpent;
    mapping(bytes4 => uint256) internal _gasLimitsForFunctionSelectors;

    address internal _senderCCIP;

    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {

        // depositIntoStrategy + mint EigenAgent: [gas: 1_950,000]
        _gasLimitsForFunctionSelectors[0xe7a050aa] = 2_200_000;
        // mintEigenAgent: [gas: 1_500_000?]
        _gasLimitsForFunctionSelectors[0xcc15a557] = 1_600_000;
        // queueWithdrawals: [gas: 529,085]
        _gasLimitsForFunctionSelectors[0x0dd8dd02] = 800_000;
        // completeQueuedWithdrawals: [gas: 769,478]
        _gasLimitsForFunctionSelectors[0x60d7faed] = 840_000;
        // delegateTo: [gas: 550,292]
        _gasLimitsForFunctionSelectors[0xeea9064b] = 600_000;
        // undelegate: [gas: ?]
        _gasLimitsForFunctionSelectors[0xda8be864] = 400_000;

        __Adminable_init();
    }

    modifier onlySenderCCIP() {
        require(msg.sender == _senderCCIP, "not called by SenderCCIP");
        _;
    }

    function getSenderCCIP() public view returns (address) {
        return _senderCCIP;
    }

    /// @param newSenderCCIP address of the SenderCCIP contract.
    function setSenderCCIP(address newSenderCCIP) public onlyOwner {
        if (newSenderCCIP == address(0))
            revert AddressZero("SenderCCIP cannot be address(0)");

        _senderCCIP = newSenderCCIP;
    }

    /// @param withdrawalTransferRoot is calculated when dispatching a completeWithdrawal message.
    function isWithdrawalTransferRootSpent(bytes32 withdrawalTransferRoot)
        public
        view
        returns (bool)
    {
        return withdrawalTransferRootsSpent[withdrawalTransferRoot];
    }

    /**
     * @dev Returns the same withdrawalRoot calculated in Eigenlayer's DelegationManager during withdrawal
     */
    function calculateWithdrawalRoot(IDelegationManager.Withdrawal memory withdrawal)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(withdrawal));
    }

    /**
     * @dev Returns the same withdrawalTransferRoot calculated in RestakingConnector.
     * @param withdrawalRoot withdrawalRoot calculated by Eigenlayer to verify withdrawals.
     * @param amount amount in the withdrawal
     * @param agentOwner owner of the EigenAgent executing completeWithdrawals
     */
    function calculateWithdrawalTransferRoot(
        bytes32 withdrawalRoot,
        uint256 amount,
        address agentOwner
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(withdrawalRoot, amount, agentOwner));
    }

    /**
     * @dev This function handles inbound L1 -> L2 completeWithdrawal messages after Eigenlayer has
     * withdrawn funds, and the L1 bridge has bridged them back to L2.
     * It receives a withdrawalTransferRoot and matches it with the committed withdrawalTransferRoot
     * to verify which user to transfer the withdrawan funds to.
     */
    function handleTransferToAgentOwner(bytes memory message)
        public
        returns (address, uint256)
    {
        TransferToAgentOwnerMsg memory transferToAgentOwnerMsg = decodeTransferToAgentOwnerMsg(message);

        bytes32 withdrawalTransferRoot = transferToAgentOwnerMsg.withdrawalTransferRoot;

        require(
            withdrawalTransferRootsSpent[withdrawalTransferRoot] == false,
            "SenderHooks.handleTransferToAgentOwner: withdrawalTransferRoot already used"
        );
        // Mark withdrawalTransferRoot as spent to prevent multiple withdrawals
        withdrawalTransferRootsSpent[withdrawalTransferRoot] = true;
        // Note: keep withdrawalTransferCommitments as a record, no need to delete.
        // delete withdrawalTransferCommitments[withdrawalTransferRoot];

        // read withdrawalTransferRoot entry that signer previously committed to.
        ISenderHooks.WithdrawalTransfer memory withdrawalTransfer =
            withdrawalTransferCommitments[withdrawalTransferRoot];

        emit SendingWithdrawalToAgentOwner(
            withdrawalTransfer.agentOwner, // signer committed when first calling completeWithdrawal
            withdrawalTransfer.amount
        );

        return (
            withdrawalTransfer.agentOwner,
            withdrawalTransfer.amount
        );
    }

    /**
     * @dev Hook that executes in outbound sendMessagePayNative calls.
     * if the outbound message is completeQueueWithdrawal, it will calculate a withdrawalTransferRoot
     * and store information about the amount and owner of the EigenAgent doing the withdrawal to
     * transfer withdrawals to later.
     * @param message is the outbound message passed to CCIP's _buildCCIPMessage function
     * @param tokenL2 token on L2 for TransferToAgentOwner callback
     */
    function beforeSendCCIPMessage(bytes memory message, address tokenL2) external onlySenderCCIP {

        bytes4 functionSelector = FunctionSelectorDecoder.decodeFunctionSelector(message);
        // When a user sends a message to `completeQueuedWithdrawal` from L2 to L1:
        if (functionSelector == IDelegationManager.completeQueuedWithdrawal.selector) {
            // 0x60d7faed
            _commitWithdrawalTransferRootInfo(message, tokenL2);
        }
    }

    function _commitWithdrawalTransferRootInfo(bytes memory message, address tokenL2) private {

        require(
            tokenL2 != address(0),
            "SenderHooks._commitWithdrawalTransferRootInfo: cannot commit tokenL2 as address(0)"
        );

        (
            IDelegationManager.Withdrawal memory withdrawal,
            , // tokensToWithdraw,
            , // middlewareTimesIndex
            bool receiveAsTokens, // receiveAsTokens
            address signer, // signer
            , // expiry
            // signature
        ) = decodeCompleteWithdrawalMsg(message);

        // only when withdrawing tokens back to L2, not for re-deposits from re-delegations
        if (receiveAsTokens) {

            // Calculate withdrawalTransferRoot: hash(withdrawalRoot, signer)
            // and commit to it on L2, so that when the withdrawalTransferRoot message is
            // returned from L1 we can lookup and verify which AgentOwner to transfer funds to.
            bytes32 withdrawalTransferRoot = calculateWithdrawalTransferRoot(
                calculateWithdrawalRoot(withdrawal),
                withdrawal.shares[0], // amount
                signer // agentOwner
            );
            // This prevents griefing attacks where other users put in withdrawalRoot entries
            // with the wrong agentOwner address, preventing completeWithdrawals

            require(
                withdrawalTransferRootsSpent[withdrawalTransferRoot] == false,
                "SenderHooks._commitWithdrawalTransferRootInfo: withdrawalTransferRoot already used"
            );

            // Commit to WithdrawalTransfer(withdrawer, amount, token, owner) before sending completeWithdrawal message,
            withdrawalTransferCommitments[withdrawalTransferRoot] = ISenderHooks.WithdrawalTransfer({
                amount: withdrawal.shares[0],
                agentOwner: signer // signer is owner of EigenAgent, used in handleTransferToAgentOwner
            });

            emit WithdrawalTransferRootCommitted(
                withdrawalTransferRoot,
                withdrawal.withdrawer, // eigenAgent
                withdrawal.shares[0], // amount
                signer // agentOwner
            );
        }
    }

    function getWithdrawalTransferCommitment(bytes32 withdrawalTransferRoot)
        external
        view
        returns (ISenderHooks.WithdrawalTransfer memory)
    {
        return withdrawalTransferCommitments[withdrawalTransferRoot];
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
    ) public onlyOwner {
        require(functionSelectors.length == gasLimits.length, "input arrays must have the same length");
        for (uint256 i = 0; i < gasLimits.length; ++i) {
            _gasLimitsForFunctionSelectors[functionSelectors[i]] = gasLimits[i];
            emit SetGasLimitForFunctionSelector(functionSelectors[i], gasLimits[i]);
        }
    }

    /**
     * @dev Retrieves estimated gasLimits for different L2 restaking functions, e.g:
     * - depositIntoStrategy(address,address,uint256) == 0xe7a050aa
     * - mintEigenAgent(bytes) == 0xcc15a557
     * - queueWithdrawals((address[],uint256[],address)[]) == 0x0dd8dd02
     * - completeQueuedWithdrawal(withdrawal,address[],uint256,bool) == 0x60d7faed
     * - delegateTo(address,(bytes,uint256),bytes32) == 0xeea9064b
     * - undelegate(address) == 0xda8be864
     * @param functionSelector bytes4 functionSelector to get estimated gasLimits for.
     * @return gasLimit a default gasLimit of 400_000 functionSelector parameter finds no matches.
     */
    function getGasLimitForFunctionSelector(bytes4 functionSelector)
        public
        view
        returns (uint256)
    {
        uint256 gasLimit = _gasLimitsForFunctionSelectors[functionSelector];
        return (gasLimit > 0) ? gasLimit : 400_000;
    }
}

