// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";

import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";
import {BaseScript} from "./BaseScript.sol";
import {EthSepolia} from "./Addresses.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";


contract QueueWithdrawalScript is BaseScript {

    uint256 deployerKey;
    address deployer;

    address staker;
    address withdrawer;
    uint256 amount;
    uint256 expiry;
    uint256 execNonce; // EigenAgent execution nonce
    uint256 withdrawalNonce; // Eigenlayer withdrawal nonce
    IEigenAgent6551 eigenAgent;
    address TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

    function run() public {
        return _run(false);
    }

    function mockrun() public {
        return _run(true);
    }

    function _run(bool isTest) private {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        readContractsAndSetupEnvironment(isTest, deployer);

        if (isTest) {
            // if isTest, deploy SenderCCIP and ReceiverCCIP again
            // or it will read stale deployed versions because of forkSelect
            vm.selectFork(ethForkId);
            (
                receiverContract,
                restakingConnector,
                agentFactory
            ) = deployReceiverOnL1Script.mockrun();

            vm.selectFork(l2ForkId);
            // mock deploy on L2 Fork
            DeploySenderOnL2Script deployOnL2Script = new DeploySenderOnL2Script();
            (senderContract,) = deployOnL2Script.mockrun();
        }

        ///////////////////////////
        // L1: Get EigenAgent
        ///////////////////////////
        vm.selectFork(ethForkId);

        eigenAgent = agentFactory.getEigenAgent(deployer);
        if (!isTest) {
            require(address(eigenAgent) != address(0), "User must have an EigenAgent");
        } else {
            vm.prank(deployer);
            eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);
        }

        execNonce = isTest ? 0 : eigenAgent.execNonce();

        ///////////////////////////
        // Parameters
        ///////////////////////////

        TARGET_CONTRACT = address(delegationManager);

        // only sending a withdrawal message, not bridging tokens.
        amount = 0 ether;
        expiry = block.timestamp + 2 hours;
        staker = address(eigenAgent);
        withdrawer = address(eigenAgent);
        // staker == withdrawer == msg.sender in StrategyManager, which is EigenAgent
        require(
            (staker == withdrawer) && (address(eigenAgent) == withdrawer),
            "staker == withdrawer == eigenAgent not satisfied"
        );

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = strategyManager.stakerStrategyShares(withdrawer, strategy);

        withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(withdrawer);
        address delegatedTo = delegationManager.delegatedTo(withdrawer);

        ///////////////////////////////////////////////////
        // Sign the queueWithdrawal payload for EigenAgent
        ///////////////////////////////////////////////////

        bytes memory withdrawalMessage;
        bytes memory messageWithSignature;

        IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal;
        queuedWithdrawal = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw,
            withdrawer: withdrawer
        });
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalArray;
        queuedWithdrawalArray = new IDelegationManager.QueuedWithdrawalParams[](1);
        queuedWithdrawalArray[0] = queuedWithdrawal;

        // create the queueWithdrawal message for Eigenlayer
        withdrawalMessage = encodeQueueWithdrawalsMsg(queuedWithdrawalArray);

        // sign the message for EigenAgent to execute Eigenlayer command
        messageWithSignature = signMessageForEigenAgentExecution(
            deployerKey,
            EthSepolia.ChainId, // destination chainid where EigenAgent lives
            TARGET_CONTRACT,
            withdrawalMessage,
            execNonce,
            expiry
        );

        ///////////////////////////
        // Broadcast to L2
        ///////////////////////////

        vm.selectFork(l2ForkId);

        uint256 gasLimit = senderHooks.getGasLimitForFunctionSelector(
            IDelegationManager.queueWithdrawals.selector
        );
        uint256 routerFees = getRouterFeesL2(
            address(receiverContract),
            string(messageWithSignature),
            address(tokenL2),
            0, // not bridging, just sending message
            gasLimit
        );
        // gas: 315,798

        vm.startBroadcast(deployerKey);

        senderContract.sendMessagePayNative{value: routerFees}(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature),
            address(tokenL2),
            amount,
            gasLimit
        );

        vm.stopBroadcast();

        string memory filePath = "script/withdrawals-queued/";
        if (isTest) {
           filePath = "test/withdrawals-queued/";
        }
        // NOTE: Tx will still be bridging after this script runs.
        // startBlock is saved after bridging completes and calls queueWithdrawal on L1.
        // Then we call getWithdrawalBlock for the correct startBlock to calculate withdrawalRoots
        saveWithdrawalInfo(
            staker,
            delegatedTo,
            withdrawer,
            withdrawalNonce,
            0, // startBlock is created later in Eigenlayer
            strategiesToWithdraw,
            sharesToWithdraw,
            bytes32(0x0), // withdrawalRoot is created later when completeWithdrawal
            bytes32(0x0), // withdrawalTransferRoot is created later
            filePath
        );
    }

}
