// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IERC20} from "@openzeppelin-v4-contracts/token/ERC20/IERC20.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {EthSepolia} from "./Addresses.sol";
import {BaseScript} from "./BaseScript.sol";


contract CompleteWithdrawalScript is BaseScript {

    uint256 deployerKey;
    address deployer;

    address staker;
    address withdrawer;
    uint256 expiry;
    bool receiveAsTokens;

    address TARGET_CONTRACT; // Contract that EigenAgent forwards calls to
    uint256 execNonce; // EigenAgent execution nonce
    IEigenAgent6551 eigenAgent;

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

        TARGET_CONTRACT = address(delegationManager);

        /////////////////////////////////////////////////////////////////
        ////// L1: Get Complete Withdrawals Params
        /////////////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        (
            eigenAgent,
            execNonce
        ) = getEigenAgentAndExecNonce(deployer);

        require(address(eigenAgent) != address(0), "User must have an EigenAgent");

        expiry = block.timestamp + 2 hours;
        staker = address(eigenAgent); // this should be EigenAgent (as in StrategyManager)
        withdrawer = address(eigenAgent);
        // staker == withdrawer == msg.sender in StrategyManager, which is EigenAgent
        require(
            (staker == withdrawer) && (address(eigenAgent) == withdrawer),
            "staker == withdrawer == eigenAgent not satisfied"
        );

        try this.readWithdrawalInfo(staker, "script/withdrawals-queued/")
            returns (IDelegationManager.Withdrawal memory withdrawal)
        {

            if (isTest) {
                // mock save a queueWithdrawalBlock
                vm.prank(deployer);
                restakingConnector.setQueueWithdrawalBlock(
                    withdrawal.staker,
                    withdrawal.nonce,
                    111
                );
            }

            // Fetch the correct withdrawal.startBlock and withdrawalRoot
            withdrawal.startBlock = uint32(restakingConnector.getQueueWithdrawalBlock(
                withdrawal.staker,
                withdrawal.nonce
            ));

            bytes32 withdrawalRoot = calculateWithdrawalRoot(withdrawal);

            IERC20[] memory tokensToWithdraw = new IERC20[](1);
            tokensToWithdraw[0] = withdrawal.strategies[0].underlyingToken();

            /////////////////////////////////////////////////////////////////
            /////// Broadcast to L2
            /////////////////////////////////////////////////////////////////
            vm.selectFork(l2ForkId);

            require(
                senderContract.allowlistedSenders(EthSepolia.ChainSelector, address(receiverContract)),
                "senderCCIP: must allowlistSender(receiverCCIP) on EthSepolia"
            );

            receiveAsTokens = true;

            {
                bytes memory completeWithdrawalMessage = encodeCompleteWithdrawalMsg(
                    withdrawal,
                    tokensToWithdraw,
                    receiveAsTokens
                );

                // sign the message for EigenAgent to execute Eigenlayer command
                bytes memory messageWithSignature = signMessageForEigenAgentExecution(
                    deployerKey,
                    address(eigenAgent),
                    EthSepolia.ChainId, // destination chainid where EigenAgent lives
                    TARGET_CONTRACT,
                    completeWithdrawalMessage,
                    execNonce,
                    expiry
                );

                Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
                tokenAmounts[0] = Client.EVMTokenAmount({
                    token: address(tokenL2),
                    amount: 0
                });

                uint256 gasLimit = senderHooks.getGasLimitForFunctionSelector(
                    IDelegationManager.completeQueuedWithdrawal.selector
                );
                uint256 routerFees = getRouterFeesL2(
                    address(receiverContract),
                    string(messageWithSignature),
                    tokenAmounts,
                    gasLimit // only sending message, not bridging tokens
                );

                vm.startBroadcast(deployerKey);

                senderContract.sendMessagePayNative{value: routerFees}(
                    EthSepolia.ChainSelector, // destination chain
                    address(receiverContract),
                    string(messageWithSignature),
                    tokenAmounts,
                    gasLimit
                );

                vm.stopBroadcast();
            }

            vm.selectFork(ethForkId);
            string memory filePath = "script/withdrawals-completed/";
            if (isTest) {
            filePath = "test/withdrawals-completed/";
            }

            saveWithdrawalInfo(
                withdrawal.staker,
                withdrawal.delegatedTo,
                withdrawal.withdrawer,
                withdrawal.nonce,
                withdrawal.startBlock,
                withdrawal.strategies,
                withdrawal.scaledShares,
                withdrawalRoot,
                filePath
            );

        } catch {
            revert("Withdrawals file not found");
        }
    }

}
