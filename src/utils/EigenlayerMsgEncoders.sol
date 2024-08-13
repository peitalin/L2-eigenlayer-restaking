//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract EigenlayerMsgEncoders {

    function encodeDepositIntoStrategyMsg(
        address strategy,
        address token,
        uint256 amount,
        address staker,
        uint256 expiry,
        bytes memory signature
    ) public pure returns (bytes memory) {
        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategy(uint256,address)")),
            strategy,
            amount
        );
        return message_bytes;
    }

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

        // structs are encoded as tuples:
        // QueuedWithdrawalParams {
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

   function encodeQueueWithdrawalsWithSignatureMsg(
        IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalWithSigParams
    ) public pure returns (bytes memory) {

        // Structs are encoded as tuples:
        // queueWithdrawalsWithSignature((address[],uint256[],address,address,bytes)[])

        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("queueWithdrawalsWithSignature((address[],uint256[],address,address,bytes)[])")),
            queuedWithdrawalWithSigParams
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
        // function completeQueuedWithdrawal(
        //     IDelegationManager.Withdrawal withdrawal,
        //     IERC20[] tokensToWithdraw,
        //     uint256 middlewareTimesIndex,
        //     bool receiveAsTokens
        // )

        // struct Withdrawal {
        //     address staker;
        //     address delegatedTo;
        //     address withdrawer;
        //     uint256 nonce;
        //     uint32 startBlock;
        //     IStrategy[] strategies;
        //     uint256[] shares;
        // }

        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("completeQueuedWithdrawal((address,address,address,uint256,address[],uint256[]),address[],uint256,bool)")),
            withdrawal,
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );

        return message_bytes;
    }
}
