// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {EthSepolia} from "./Addresses.sol";
import {BaseScript} from "./BaseScript.sol";


// UX Flow for Delegating, Undelegating, and Re-depositing:
// 1) undelegate
// 2) re-delegateTo another Operator
// 3) re-deposit with completeWithdrawal(receiveAsToken=false)
//
// Then you will be delegated to the new operator. Steps (2) and (3) are interchangeable

contract UndelegateScript is BaseScript {

    function run() public {
        return _run(false);
    }

    function mockrun() public {
        return _run(true);
    }

    function _run(bool isTest) private {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        uint256 operatorKey = vm.envUint("OPERATOR_KEY");
        address operator = vm.addr(operatorKey);
        address TARGET_CONTRACT = address(delegationManager);

        readContractsFromDisk();

        vm.selectFork(ethForkId);

        // Get User's EigenAgent
        IEigenAgent6551 eigenAgent = agentFactory.getEigenAgent(deployer);
        require(
            strategyManager.stakerStrategyShares(address(eigenAgent), strategy) >= 0,
            "EigenAgent has no deposit in Eigenlayer"
        );

        if (!isTest) {
            require(delegationManager.isOperator(operator), "operator must be registered");
            require(
                delegationManager.delegatedTo(address(eigenAgent)) == address(operator),
                "EigenAgent not delegatedTo any operators"
            );
        }

        ///////////////////////////////////////
        // Valid withdrawalRoots: record the following before sending undelegate message:
        //     delegatedTo
        //     nonce
        //     sharesToWithdraw
        //     strategyToWithdraw
        //     withdrawer
        ///////////////////////////////////////

        uint256 execNonce = eigenAgent.execNonce();
        uint256 sig_expiry = block.timestamp + 2 hours;
        uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(address(eigenAgent));
        address withdrawer = address(eigenAgent);

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);
        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = strategyManager.stakerStrategyShares(withdrawer, strategy);

        address delegatedTo = delegationManager.delegatedTo(address(eigenAgent));

        /////////////////////////////////////////////////////////////////
        /////// Broadcast Undelegate message on L2
        /////////////////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);

        // Encode undelegate message, and append user signature for EigenAgent execution
        bytes memory messageWithSignature_DT = signMessageForEigenAgentExecution(
            deployerKey,
            EthSepolia.ChainId, // destination chainid where EigenAgent lives
            TARGET_CONTRACT, // DelegationManager.delegateTo()
            encodeUndelegateMsg(address(eigenAgent)),
            execNonce,
            sig_expiry
        );

        topupEthBalance(address(senderContract));

        uint256 gasLimit = senderHooks.getGasLimitForFunctionSelector(
            IDelegationManager.undelegate.selector
        );

        senderContract.sendMessagePayNative{
            value: getRouterFeesL2(
                address(receiverContract),
                string(messageWithSignature_DT),
                address(tokenL2),
                0, // not bridging, just sending message
                gasLimit
            )
        }(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_DT),
            address(tokenL2),
            0, // not bridging, just sending message
            gasLimit
        );

        vm.stopBroadcast();

        /////////////////////////////////////////////////////////////////
        /////// Save undelegate withdrawal details
        /////////////////////////////////////////////////////////////////

        string memory filePath = "script/withdrawals-undelegated/";
        if (isTest) {
           filePath = "test/withdrawals-undelegated/";
        }

        // NOTE: Tx will still be bridging after this script runs.
        // startBlock is saved after bridging completes and calls queueWithdrawal on L1.
        // We must call getWithdrawalBlock for the correct startBlock to calculate withdrawalRoots
        saveWithdrawalInfo(
            address(eigenAgent), // staker
            delegatedTo,
            withdrawer,
            withdrawalNonce,
            0, // startBlock is created later in Eigenlayer
            strategiesToWithdraw,
            sharesToWithdraw,
            bytes32(0x0), // withdrawalRoot is created later (requires startBlock)
            bytes32(0x0), // withdrawalAgenOwnerRoot not used in delegations
            filePath
        );
    }
}
