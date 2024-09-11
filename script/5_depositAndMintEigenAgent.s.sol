// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";

import {EthSepolia} from "./Addresses.sol";
import {BaseScript} from "./BaseScript.sol";

import {console} from "forge-std/Test.sol";

contract DepositAndMintEigenAgentScript is BaseScript {

    uint256 deployerKey;
    address deployer;

    address TARGET_CONTRACT; // Contract that EigenAgent forwards calls to
    uint256 execNonce = 0;
    IEigenAgent6551 eigenAgent;

    function run() public {
        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        readContractsAndSetupEnvironment(false, deployer);
        return _run();
    }

    function mockrun(uint256 mockKey) public {
        deployerKey = mockKey;
        deployer = vm.addr(mockKey);
        readContractsAndSetupEnvironment(true, deployer);
        return _run();
    }

    function _run() private {

        TARGET_CONTRACT = address(strategyManager);

        //////////////////////////////////////////////////////////
        /// L1: Get Deposit Inputs
        //////////////////////////////////////////////////////////

        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        console.log("deployer:", deployer);

        (
            eigenAgent,
            execNonce
        ) = getEigenAgentAndExecNonce(deployer);

        require(address(eigenAgent) == address(0), "User already has an EigenAgent");
        /// agentFactory will spawn an EigenAgent after bridging automatically
        /// if user does not already have an EigenAgent NFT on L1.
        /// but this costs more gas to be sent up-front for CCIP
        /// Nonce is then 0.
        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        /// L2: Dispatch Call
        //////////////////////////////////////////////////////
        // Make sure we are on BaseSepolia Fork
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);

        uint256 amount = 0.0619 ether;
        uint256 expiry = block.timestamp + 1 hours;

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

        tokenL2.approve(address(senderContract), amount);

        uint256 gasLimit = senderHooks.getGasLimitForFunctionSelector(
            IStrategyManager.depositIntoStrategy.selector
        );

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
            gasLimit // use default gasLimit if 0
        );

        vm.stopBroadcast();
    }
}
