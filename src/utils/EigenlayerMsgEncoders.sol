//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";


contract EigenlayerMsgEncoders {

    function encodeDepositIntoStrategyWithSignatureMsg(
        address strategy,
        address token,
        uint256 amount,
        address staker,
        uint256 expiry,
        bytes memory signature
    ) public pure returns (bytes memory) {

        // encode message payload
        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")),
            strategy,
            token,
            amount,
            staker,
            expiry,
            signature
        );
        // CCIP turns the message into string when sending
        // bytes memory message = abi.encode(string(message_bytes));
        return message_bytes;
    }

    function encodeQueueWithdrawalMsg(
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams
    ) public pure returns (bytes memory) {

        ///// Function signature: structs are encoded as tuples:
        //
        // function queueWithdrawals(QueuedWithdrawalParams[] q)
        // where q = QueuedWithdrawalParams {
        //     IStrategy[] strategies;
        //     uint256[] shares;
        //     address withdrawer;
        // }

        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("queueWithdrawals((address[],uint256[],address)[])")),
            queuedWithdrawalParams
        );

        return message_bytes;
    }

    function encodeCompleteWithdrawalMsg(
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams
    ) public pure returns (bytes memory) {

        ///// Function signature: structs are encoded as tuples:
        //
        // function queueWithdrawals(QueuedWithdrawalParams[] q)
        // where q = QueuedWithdrawalParams {
        //     IStrategy[] strategies;
        //     uint256[] shares;
        //     address withdrawer;
        // }

        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("queueWithdrawals((address[],uint256[],address)[])")),
            queuedWithdrawalParams
        );

        return message_bytes;
    }
}
