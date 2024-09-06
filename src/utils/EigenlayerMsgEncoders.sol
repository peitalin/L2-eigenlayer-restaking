//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISenderHooks} from "../interfaces/ISenderHooks.sol";
import {IRestakingConnector} from "../interfaces/IRestakingConnector.sol";


library EigenlayerMsgEncoders {

    function encodeDepositIntoStrategyMsg(
        address strategy,
        address token,
        uint256 amount
    ) public pure returns (bytes memory) {

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "depositIntoStrategy(address,address,uint256)" == 0xe7a050aa
            IStrategyManager.depositIntoStrategy.selector,
            strategy,
            token,
            amount
        );
        return message_bytes;
    }

    function encodeQueueWithdrawalsMsg(
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams
    ) public pure returns (bytes memory) {

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "queueWithdrawals((address[],uint256[],address)[])"
            IDelegationManager.queueWithdrawals.selector,
            queuedWithdrawalParams
        );

        return message_bytes;
    }

    function encodeCompleteWithdrawalMsg(
        IDelegationManager.Withdrawal memory withdrawal,
        IERC20[] memory tokensToWithdraw,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    ) public pure returns (bytes memory) {

        // Function Signature:
        //     completeQueuedWithdrawal(
        //         IDelegationManager.Withdrawal withdrawal,
        //         IERC20[] tokensToWithdraw,
        //         uint256 middlewareTimesIndex,
        //         bool receiveAsTokens
        //     )
        // Where:
        //     struct Withdrawal {
        //         address staker;
        //         address delegatedTo;
        //         address withdrawer;
        //         uint256 nonce;
        //         uint32 startBlock;
        //         IStrategy[] strategies;
        //         uint256[] shares;
        //     }

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],uint256,bool)" == 0x60d7faed
            IDelegationManager.completeQueuedWithdrawal.selector,
            withdrawal,
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );

        return message_bytes;
    }

    function encodeDelegateTo(
        address operator,
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) public pure returns (bytes memory) {

        // Function Signature:
        //     delegateTo(
        //         address operator,
        //         SignatureWithExpiry memory approverSignatureAndExpiry,
        //         bytes32 approverSalt
        //     )
        // Where:
        //     struct SignatureWithExpiry {
        //         bytes signature;
        //         uint256 expiry;
        //     }

        // 0000000000000000000000000000000000000000000000000000000000000020
        // 0000000000000000000000000000000000000000000000000000000000000164
        // 0xeea9064b                                                       [96] function selector
        // 00000000000000000000000071c6f7ed8c2d4925d0baf16f6a85bb1736d412eb
        // 00000000000000000000000071c6f7ed8c2d4925d0baf16f6a85bb1736d41333
        // 00000000000000000000000000000000000000000000000000000000000000a0
        // 0000000000000000000000000000000000000000000000000000000000000100
        // 0000000000000000000000000000000000000000000000000000000000004444
        // 0000000000000000000000000000000000000000000000000000000000000040
        // 0000000000000000000000000000000000000000000000000000000000000000
        // 0000000000000000000000000000000000000000000000000000000000000000
        // 0000000000000000000000000000000000000000000000000000000000000040
        // 0000000000000000000000000000000000000000000000000000000000000001
        // 0000000000000000000000000000000000000000000000000000000000000000

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "delegateTo(address,(bytes,uint256),bytes32)" == 0xeea9064b
            IDelegationManager.delegateTo.selector,
            operator,
            approverSignatureAndExpiry,
            approverSalt
        );
        return message_bytes;
    }

    function encodeUndelegateMsg(address staker) public pure returns (bytes memory) {
        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "undelegate(address)" == 0xda8be864
            IDelegationManager.undelegate.selector,
            staker
        );
        return message_bytes;
    }

    function encodeMintEigenAgent(address recipient) public pure returns (bytes memory) {

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "mintEigenAgent(bytes)" == 0xcc15a557
            IRestakingConnector.mintEigenAgent.selector,
            recipient
        );
        return message_bytes;
    }

    /*
     *
     *         L2 Withdrawal Transfers
     *
     *
    */

    function calculateWithdrawalTransferRoot(
        bytes32 withdrawalRoot,
        uint256 amount,
        address agentOwner // signer
    ) public pure returns (bytes32) {
        // encode signer into withdrawalTransferRoot
        return keccak256(abi.encode(withdrawalRoot, amount, agentOwner));
    }

    function encodeHandleTransferToAgentOwnerMsg(
        bytes32 withdrawalTransferRoot
    ) public pure returns (bytes memory) {

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "handleTransferToAgentOwner(bytes)" == 0xd8a85b48
            ISenderHooks.handleTransferToAgentOwner.selector,
            withdrawalTransferRoot
        );
        return message_bytes;
    }
}
