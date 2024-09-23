// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {EthSepolia} from "./Addresses.sol";
import {BaseScript} from "./BaseScript.sol";


contract RedepositScript is BaseScript {

    uint256 deployerKey;
    address deployer;

    address public staker;
    address public withdrawer;
    uint256 public amount;
    uint256 public sigExpiry;
    uint256 public middlewareTimesIndex; // not used yet, for slashing
    bool public receiveAsTokens;

    uint256 public execNonce; // EigenAgent execution nonce
    IEigenAgent6551 public eigenAgent;
    address public TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

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

        // Get EigenAgent
        eigenAgent = agentFactory.getEigenAgent(deployer);
        require(address(eigenAgent) != address(0), "User must have an EigenAgent");

        amount = 0 ether; // only sending message, not bridging tokens.
        sigExpiry = block.timestamp + 2 hours;
        execNonce = eigenAgent.execNonce();
        staker = address(eigenAgent); // this should be EigenAgent
        withdrawer = address(eigenAgent);
        require(
            (staker == withdrawer) && (address(eigenAgent) == withdrawer),
            "staker == withdrawer == eigenAgent not satisfied"
        );

        try this.readWithdrawalInfo(staker, "script/withdrawals-undelegated/")
            returns (IDelegationManager.Withdrawal memory withdrawal)
        {

            // Fetch the correct withdrawal.startBlock and withdrawalRoot
            withdrawal.startBlock = uint32(restakingConnector.getQueueWithdrawalBlock(
                withdrawal.staker,
                withdrawal.nonce
            ));

            bytes32 withdrawalRootCalculated = delegationManager.calculateWithdrawalRoot(withdrawal);

            IERC20[] memory tokensToWithdraw = new IERC20[](1);
            tokensToWithdraw[0] = withdrawal.strategies[0].underlyingToken();

            /////////////////////////////////////////////////////////////////
            /////// Broadcast to L2
            /////////////////////////////////////////////////////////////////
            vm.selectFork(l2ForkId);

            require(
                senderContract.allowlistedSenders(address(receiverContract)),
                "senderCCIP: must allowlistSender(receiverCCIP)"
            );

            middlewareTimesIndex = 0; // not used yet, for slashing
            receiveAsTokens = false;
            // receiveAsTokens == false to redeposit queuedWithdrawal (from undelegating)
            // back into Eigenlayer.

            require(
                receiveAsTokens == false,
                "receiveAsTokens must be false to re-deposit undelegated deposit back in Eigenlayer"
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            bytes memory messageWithSignature = signMessageForEigenAgentExecution(
                deployerKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                TARGET_CONTRACT,
                encodeCompleteWithdrawalMsg(
                    withdrawal,
                    tokensToWithdraw,
                    middlewareTimesIndex,
                    receiveAsTokens
                ),
                execNonce,
                sigExpiry
            );

            uint256 gasLimit = senderHooks.getGasLimitForFunctionSelector(
                IDelegationManager.completeQueuedWithdrawal.selector
            );
            uint256 routerFees = getRouterFeesL2(
                address(receiverContract),
                string(messageWithSignature),
                address(tokenL2),
                0, // not bridging, just sending message
                gasLimit
            );

            vm.startBroadcast(deployerKey);

            senderContract.sendMessagePayNative{value: routerFees}(
                EthSepolia.ChainSelector, // destination chain
                address(receiverContract),
                string(messageWithSignature),
                address(tokenL2),
                amount,
                0 // use default gasLimit for this function
            );

            vm.stopBroadcast();


            vm.selectFork(ethForkId);
            string memory filePath = "script/withdrawals-redeposited/";
            if (isTest) {
                filePath = "test/withdrawals-redeposited/";
            }

            saveWithdrawalInfo(
                withdrawal.staker,
                withdrawal.delegatedTo,
                withdrawal.withdrawer,
                withdrawal.nonce,
                withdrawal.startBlock,
                withdrawal.strategies,
                withdrawal.shares,
                withdrawalRootCalculated,
                bytes32(0x0), // withdrawalAgenOwnerRoot not used in delegations
                filePath
            );

        } catch {
            revert("Withdrawals file not found");
        }
    }
}
