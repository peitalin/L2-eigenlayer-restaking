// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {Adminable} from "./utils/Adminable.sol";

import {ISenderUtils} from "./interfaces/ISenderUtils.sol";
import {EigenlayerMsgDecoders, TransferToAgentOwnerMsg} from "./utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "./utils/EigenlayerMsgEncoders.sol";
import {HashAgentOwnerRoot} from "./utils/HashAgentOwnerRoot.sol";



contract SenderUtils is Initializable, Adminable, EigenlayerMsgDecoders {

    event SendingWithdrawalToAgentOwner(address indexed, uint256 indexed, address indexed);
    event WithdrawalCommitted(bytes32 indexed, address indexed, uint256 indexed);
    event SetGasLimitForFunctionSelector(bytes4 indexed, uint256 indexed);

    mapping(bytes32 => ISenderUtils.WithdrawalTransfer) public withdrawalTransferCommittments;
    mapping(bytes32 => bool) public withdrawalRootsSpent;

    mapping(bytes4 => uint256) internal _gasLimitsForFunctionSelectors;

    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {

        // depositIntoStrategy + mint agent: [gas: 1_950_000]
        _gasLimitsForFunctionSelectors[0xe7a050aa] = 2_200_000;
        // depositIntoStrategyWithSignature: [gas: 713_400]
        _gasLimitsForFunctionSelectors[0x32e89ace] = 800_000;
        // queueWithdrawals: [gas: x]
        _gasLimitsForFunctionSelectors[0x0dd8dd02] = 800_000;
        // completeQueuedWithdrawals: [gas: 645_948]
        _gasLimitsForFunctionSelectors[0x60d7faed] = 800_000;
        // delegateTo: [gas: ?]
        _gasLimitsForFunctionSelectors[0xeea9064b] = 600_000;
        // delegateToBySignature: [gas: ?]
        _gasLimitsForFunctionSelectors[0x7f548071] = 600_000;
        // undelegate: [gas: ?]
        _gasLimitsForFunctionSelectors[0xda8be864] = 400_000;

        __Adminable_init();
    }

    function handleTransferToAgentOwner(bytes memory message) public returns (
        address,
        uint256,
        address
    ) {

        TransferToAgentOwnerMsg memory transferToAgentOwnerMsg = decodeTransferToAgentOwnerMsg(message);

        bytes32 withdrawalRoot = transferToAgentOwnerMsg.withdrawalRoot;
        address agentOwner = transferToAgentOwnerMsg.agentOwner;
        bytes32 agentOwnerRoot = transferToAgentOwnerMsg.agentOwnerRoot;

        require(
            HashAgentOwnerRoot.hashAgentOwnerRoot(withdrawalRoot, agentOwner) == agentOwnerRoot,
            "SenderUtils.handleTransferToAgentOwner: invalid agentOwnerRoot"
        );

        ISenderUtils.WithdrawalTransfer memory withdrawalTransfer = withdrawalTransferCommittments[withdrawalRoot];

        // mark the withdrawalRoot as spent to prevent multiple withdrawals
        withdrawalRootsSpent[withdrawalRoot] = true;
        delete withdrawalTransferCommittments[withdrawalRoot];

        emit SendingWithdrawalToAgentOwner(
            agentOwner,
            withdrawalTransfer.amount, // amount
            withdrawalTransfer.tokenDestination // tokenL2Address
        );

        return (
            agentOwner,
            withdrawalTransfer.amount, // amount
            withdrawalTransfer.tokenDestination // tokenL2Address
        );
    }

    function calculateWithdrawalRoot(
        IDelegationManager.Withdrawal memory withdrawal
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(withdrawal));
    }

    function commitWithdrawalRootInfo(bytes memory message, address tokenDestinationL2) public {

            require(tokenDestinationL2 != address(0), "cannot commit tokenL2 as address(0)");

            (
                IDelegationManager.Withdrawal memory withdrawal
                , // tokensToWithdraw,
                , // middlewareTimesIndex
                , // receiveAsTokens
                , // signer
                , // expiry
                , // signature
            ) = decodeCompleteWithdrawalMsg(message);

            bytes32 withdrawalRoot = calculateWithdrawalRoot(withdrawal);

            // Check for spent withdrawalRoots to prevent wasted CCIP message
            // as it will fail to withdraw from Eigenlayer
            require(
                withdrawalRootsSpent[withdrawalRoot] == false,
                "withdrawalRoot has already been used"
            );

            // Commit to WithdrawalTransfer(withdrawer, amount, token) before sending completeWithdrawal message,
            // so that when the message returns with withdrawalRoot, we use it to lookup (withdrawer, amount)
            // to transfer the bridged withdrawn funds to.
            withdrawalTransferCommittments[withdrawalRoot] = ISenderUtils.WithdrawalTransfer({
                withdrawer: withdrawal.withdrawer,
                amount: withdrawal.shares[0],
                tokenDestination: tokenDestinationL2
            });

            emit WithdrawalCommitted(withdrawalRoot, withdrawal.withdrawer, withdrawal.shares[0]);
    }

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

