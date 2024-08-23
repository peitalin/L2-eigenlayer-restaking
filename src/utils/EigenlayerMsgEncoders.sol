//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {QueuedWithdrawalWithSignatureParams} from "../interfaces/IEigenlayerMsgDecoders.sol";


library EigenlayerMsgEncoders {

    /*
     *
     *         EigenAgent Messages
     *
     *
    */

    // msg to CCIP for EigenAgent
    function encodeDepositWithSignature6551Msg(
        address strategy,
        address token,
        uint256 amount,
        address staker,
        uint256 expiry,
        bytes memory signature
    ) public pure returns (bytes memory) {
        // encode message payload
        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("depositWithSignature6551(address,address,uint256,address,uint256,bytes)")),
            strategy,
            token,
            amount,
            staker,
            expiry,
            signature
        );
        return message_bytes;
    }

    // used by EigenAgent
    function encodeDepositIntoStrategyMsg(
        address strategy,
        address token,
        uint256 amount
    ) public pure returns (bytes memory) {
        // encode message payload
        bytes memory message_bytes = abi.encodeWithSelector(
            // bytes4(keccak256("depositIntoStrategy(address,address,uint256)")),
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

    /*
     *
     *         Standard Messages
     *
     *
    */

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

    function encodeQueueWithdrawalsWithSignatureMsg(
        QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalWithSigArray
    ) public pure returns (bytes memory) {

        // Structs are encoded as tuples:
        // queueWithdrawalsWithSignature((address[],uint256[],address,address,bytes)[])
        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("queueWithdrawalsWithSignature((address[],uint256[],address,address,bytes)[])")),
            queuedWithdrawalWithSigArray
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
            bytes4(keccak256("completeQueuedWithdrawal((address,address,address,uint256,address[],uint256[]),address[],uint256,bool)")),
            withdrawal,
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );

        return message_bytes;
    }

    function encodeTransferToStakerMsg(bytes32 withdrawalRoot) public pure returns (bytes memory) {
        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("transferToStaker(bytes32)")),
            withdrawalRoot
        );
        return message_bytes;
    }


    function encodeDelegateToBySignature(
        address staker,
        address operator,
        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry,
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) public pure returns (bytes memory) {

        // function delegateToBySignature(
        //     address staker,
        //     address operator,
        //     SignatureWithExpiry memory stakerSignatureAndExpiry,
        //     SignatureWithExpiry memory approverSignatureAndExpiry,
        //     bytes32 approverSalt
        // )

        // 0000000000000000000000000000000000000000000000000000000000000020
        // 0000000000000000000000000000000000000000000000000000000000000164
        // 7f548071                                                         [96] function selector
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

        // 0x7f548071
        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("delegateToBySignature(address,address,(bytes,uint256),(bytes,uint256),bytes32)")),
            staker,
            operator,
            stakerSignatureAndExpiry,
            approverSignatureAndExpiry,
            approverSalt
        );
        return message_bytes;
    }

    function encodeUndelegateMsg(address staker) public pure returns (bytes memory) {
        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("undelegate(address)")),
            staker
        );
        return message_bytes;
    }
}
