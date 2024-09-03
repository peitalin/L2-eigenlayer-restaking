//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISenderUtils} from "../interfaces/ISenderUtils.sol";
import {IRestakingConnector} from "../interfaces/IRestakingConnector.sol";


library EigenlayerMsgEncoders {

    // used by EigenAgent -> Eigenlayer
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

    /*
     *
     *         Standard Messages
     *
     *
    */

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

    function calculateWithdrawalAgentOwnerRoot(
        bytes32 withdrawalRoot,
        address agentOwner // signer
    ) public pure returns (bytes32) {
        // encode signer into withdrawalAgentOwnerRoot
        return keccak256(abi.encode(withdrawalRoot, agentOwner));
    }

    function encodeHandleTransferToAgentOwnerMsg(
        bytes32 withdrawalRoot,
        address signer
    ) public pure returns (bytes memory) {

        bytes memory message_bytes = abi.encodeWithSelector(
            // cast sig "handleTransferToAgentOwner(bytes)" == 0xd8a85b48
            ISenderUtils.handleTransferToAgentOwner.selector,
            calculateWithdrawalAgentOwnerRoot(withdrawalRoot, signer)
        );
        return message_bytes;
    }

    function encodeDelegateTo(
        address operator,
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) public pure returns (bytes memory) {

        // function delegateTo(
        //     address operator,
        //     SignatureWithExpiry memory approverSignatureAndExpiry,
        //     bytes32 approverSalt
        // )
        // struct SignatureWithExpiry {
        //     // the signature itself, formatted as a single bytes object
        //     bytes signature;
        //     // the expiration timestamp (UTC) of the signature
        //     uint256 expiry;
        // }

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
            // cast sig "undelegate(address)"
            IDelegationManager.undelegate.selector,
            staker
        );
        return message_bytes;
    }
}
