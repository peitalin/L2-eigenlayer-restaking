// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {BaseScript} from "./BaseScript.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";


contract DepositIntoStrategyScript is BaseScript {

    IEigenAgent6551 public eigenAgent;
    address public TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

    // This script assumes you already have an EigenAgent
    function run() public {
        return _run(false);
    }

    function mockrun() public {
        return _run(true);
    }

    function _run(bool isTest) private {

        readContractsFromDisk();

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);


        TARGET_CONTRACT = address(strategyManager);

        //////////////////////////////////////////////////////////
        /// L1: Get Deposit Inputs
        //////////////////////////////////////////////////////////

        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        uint256 execNonce = 0;
        /// ReceiverCCIP spawns an EigenAgent when CCIP message reaches L1
        /// if user does not already have an EigenAgent NFT on L1.  Nonce is then 0.
        (
            eigenAgent,
            execNonce
        ) = getEigenAgentAndExecNonce(deployer);

        require(address(eigenAgent) != address(0), "User must have an EigenAgent");

        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        /// L2: Dispatch Call
        //////////////////////////////////////////////////////
        // Make sure we are on BaseSepolia Fork
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);

        uint256 amount = 0.00797 ether;
        uint256 expiry = block.timestamp + 45 minutes;
        bytes memory depositMessage;
        bytes memory messageWithSignature;

        {
            depositMessage = encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signMessageForEigenAgentExecution(
                deployerKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                TARGET_CONTRACT, // StrategyManager is the target
                depositMessage,
                execNonce,
                expiry
            );
        }

        // Check L2 CCIP-BnM balances
        if (tokenL2.balanceOf(deployer) < 1 ether || isTest) {
            IERC20_CCIPBnM(address(tokenL2)).drip(deployer);
        }

        topupEthBalance(address(senderContract));
        // token approval
        tokenL2.approve(address(senderContract), amount);
        // get ETH fees to send

        uint256 gasLimit = 800_000;
        // set gasLimit = 0 to use default values

        senderContract.sendMessagePayNative{
            value: getRouterFeesL2(
                address(receiverContract),
                string(messageWithSignature),
                address(tokenL2),
                amount,
                gasLimit
            )
        }(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature),
            address(tokenL2),
            amount,
            gasLimit
        );

        vm.stopBroadcast();
    }
}
