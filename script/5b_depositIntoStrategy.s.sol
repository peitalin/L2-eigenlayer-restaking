// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {BaseScript} from "./BaseScript.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";


contract DepositIntoStrategyScript is BaseScript {

    uint256 deployerKey;
    address deployer;

    IEigenAgent6551 eigenAgent;
    address TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

    // This script assumes you already have an EigenAgent
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

        TARGET_CONTRACT = address(strategyManager);

        //////////////////////////////////////////////////////////
        /// L1: Get Deposit Inputs
        //////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        uint256 execNonce = 0;
        /// ReceiverCCIP spawns an EigenAgent when CCIP message reaches L1
        /// if user does not already have an EigenAgent NFT on L1.  Nonce is then 0.
        (
            eigenAgent,
            execNonce
        ) = getEigenAgentAndExecNonce(deployer);

        require(address(eigenAgent) != address(0), "User must have an EigenAgent");

        //////////////////////////////////////////////////////
        /// L2: Dispatch Call
        //////////////////////////////////////////////////////
        // Make sure we are on BaseSepolia Fork
        vm.selectFork(l2ForkId);

        uint256 amount = 0.00797 ether;
        uint256 expiry = block.timestamp + 45 minutes;

        // sign the message for EigenAgent to execute Eigenlayer command
        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            deployerKey,
            EthSepolia.ChainId, // destination chainid where EigenAgent lives
            TARGET_CONTRACT, // StrategyManager is the target
            encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            ),
            execNonce,
            expiry
        );

        uint256 gasLimit = 570_000; // gas: 564,969
        uint256 routerFees = getRouterFeesL2(
            address(receiverContract),
            string(messageWithSignature),
            address(tokenL2),
            amount,
            gasLimit
        );

        vm.startBroadcast(deployerKey);
        // token approval
        tokenL2.approve(address(senderContract), amount);

        senderContract.sendMessagePayNative{value: routerFees}(
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
