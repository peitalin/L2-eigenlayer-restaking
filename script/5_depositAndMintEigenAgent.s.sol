// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {console} from "forge-std/Test.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {EthSepolia} from "./Addresses.sol";
import {BaseScript} from "./BaseScript.sol";


contract DepositAndMintEigenAgentScript is BaseScript {

    uint256 deployerKey;
    address deployer;

    uint256 stakerKey;
    address staker;

    address TARGET_CONTRACT; // Contract that EigenAgent forwards calls to
    uint256 execNonce = 0;
    IEigenAgent6551 eigenAgent;

    function run() public {
        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        stakerKey = deployerKey;
        staker = deployer;
        return _run(false);
    }

    function mockrun(uint256 mockKey) public {
        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        stakerKey = mockKey;
        staker = vm.addr(mockKey);
        return _run(true);
    }

    function _run(bool isTest) private {

        readContractsAndSetupEnvironment(false, deployer);

        TARGET_CONTRACT = address(strategyManager);

        vm.selectFork(ethForkId);
        (
            eigenAgent,
            execNonce
        ) = getEigenAgentAndExecNonce(deployer);

        if (address(eigenAgent) != address(0)) {
            // Check if deployer already has an EigenAgent.
            // If so, generate a new account (to test minting new EigenAgents)
            // AgentFactory will spawn an EigenAgent after bridging automatically
            // If user does not already have an EigenAgent NFT on L1.
            stakerKey = vm.randomUint() / 2 + 1; // EIP-2: secp256k1 curve order / 2
            staker = vm.addr(stakerKey);
            execNonce = 0;
            // Send random new account some ether to mint an EigenAgent
            vm.selectFork(l2ForkId);
            vm.startBroadcast(deployerKey);
            if (isTest) {
                (bool success, bytes memory res) = staker.call{value: 0.1 ether}("");
            } else {
                (bool success, bytes memory res) = staker.call{value: 0.02 ether}("");
            }
            IERC20_CCIPBnM(address(tokenL2)).drip(staker);
            vm.stopBroadcast();
        }

        //////////////////////////////////////////////////////
        /// L2: Dispatch Call
        //////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        uint256 amount = 0.0117 ether;
        uint256 expiry = block.timestamp + 1 hours;

        // sign the message for EigenAgent to execute Eigenlayer command
        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            stakerKey,
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

        uint256 gasLimit = senderHooks.getGasLimitForFunctionSelector(
            IStrategyManager.depositIntoStrategy.selector
        );
        uint256 routerFees = getRouterFeesL2(
            address(receiverContract),
            string(messageWithSignature),
            address(tokenL2),
            amount,
            gasLimit
        );
        console.log("Router fees:", routerFees);

        vm.startBroadcast(stakerKey);
        {
            tokenL2.approve(address(senderContract), amount);

            senderContract.sendMessagePayNative{value: routerFees}(
                EthSepolia.ChainSelector, // destination chain
                address(receiverContract),
                string(messageWithSignature),
                address(tokenL2),
                amount,
                gasLimit // use default gasLimit if 0
            );
        }
        vm.stopBroadcast();
    }
}
