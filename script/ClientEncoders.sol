//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin-v47-contracts/token/ERC20/IERC20.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer-contracts/interfaces/ISignatureUtilsMixin.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";

import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";

/// Note: Workaround for libraries not playing well with multi-fork environments + scripting in foundry
/// This contract is a copy of EigenlayerMsgEncoders.sol
contract ClientEncoders {

    function encodeDepositIntoStrategyMsg(
        address strategy,
        address token,
        uint256 amount
    ) public pure returns (bytes memory) {

        return abi.encodeWithSelector(
            // cast sig "depositIntoStrategy(address,address,uint256)" == 0xe7a050aa
            IStrategyManager.depositIntoStrategy.selector,
            strategy,
            token,
            amount
        );
    }

    function encodeQueueWithdrawalsMsg(
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams
    ) public pure returns (bytes memory) {

        return abi.encodeWithSelector(
            // cast sig "queueWithdrawals((address[],uint256[],address)[])" == 0x0dd8dd02
            IDelegationManager.queueWithdrawals.selector,
            queuedWithdrawalParams
        );
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
        bool receiveAsTokens
    ) public pure returns (bytes memory) {

        // Function Signature:
        //     completeQueuedWithdrawal(
        //         IDelegationManager.Withdrawal withdrawal,
        //         IERC20[] tokensToWithdraw,
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
        //         uint256[] scaledShares;
        //     }

        return abi.encodeWithSelector(
            // cast sig "completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],bool)" == 0xe4cc3f90
            IDelegationManager.completeQueuedWithdrawal.selector,
            withdrawal,
            tokensToWithdraw,
            receiveAsTokens
        );
    }

    function encodeCompleteWithdrawalsMsg(
        IDelegationManager.Withdrawal[] memory withdrawals,
        IERC20[][] memory tokens,
        bool[] memory receiveAsTokens
    ) public pure returns (bytes memory) {

        // Function Signature:
        //     completeQueuedWithdrawals(
        //         Withdrawal[] withdrawals,
        //         IERC20[][] tokens,
        //         bool[] receiveAsTokens
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

        return abi.encodeWithSelector(
            // cast sig "completeQueuedWithdrawals((address,address,address,uint256,uint32,address[],uint256[])[],address[][],uint256[],bool[])" == 0x33404396
            IDelegationManager.completeQueuedWithdrawals.selector,
            withdrawals,
            tokens,
            receiveAsTokens
        );
    }

    function calculateWithdrawalRoot(IDelegationManager.Withdrawal memory withdrawal)
        public
        pure
        returns (bytes32) {
        return keccak256(abi.encode(withdrawal));
    }

    function encodeTransferToAgentOwnerMsg(address agentOwner) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            // cast sig "handleTransferToAgentOwner(address)" == 0x43598c8c
            ISenderHooks.handleTransferToAgentOwner.selector,
            agentOwner
        );
    }

    function encodeDelegateTo(
        address operator,
        ISignatureUtilsMixinTypes.SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) public pure returns (bytes memory) {

        // function delegateTo(
        //     address operator,
        //     SignatureWithExpiry memory approverSignatureAndExpiry,
        //     bytes32 approverSalt
        // )

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

        return abi.encodeWithSelector(
            IDelegationManager.delegateTo.selector,
            operator,
            approverSignatureAndExpiry,
            approverSalt
        );
    }

    function encodeUndelegateMsg(address staker) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            // bytes4(keccak256("undelegate(address)")),
            IDelegationManager.undelegate.selector,
            staker
        );
    }

    function encodeMintEigenAgentMsg(address recipient) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            // cast sig "mintEigenAgent(bytes)" == 0xcc15a557
            IRestakingConnector.mintEigenAgent.selector,
            recipient
        );
    }

    function encodeProcessClaimMsg(
        IRewardsCoordinator.RewardsMerkleClaim memory claim,
        address recipient
    ) public pure returns (bytes memory) {
        return abi.encodeWithSelector(
            // cast sig "processClaim((uint32,uint32,bytes,(address,bytes32),uint32[],bytes[],(address,uint256)[]), address)" == 0x3ccc861d
            IRewardsCoordinator.processClaim.selector,
            claim,
            recipient
        );
    }

}

