// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/Test.sol";
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
        ) = getEigenAgentAndExecNonce(staker);

        require(address(eigenAgent) == address(0), "User already has an EigenAgent");

        //////////////////////////////////////////////////////
        /// L2: Fund staker account
        //////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);
        if (isTest) {
            vm.deal(staker, 1 ether);
            (bool success, ) = staker.call{value: 0.5 ether}("");
        } else {
            if (address(staker).balance < 0.04 ether) {
                (bool success, ) = staker.call{value: 0.03 ether}("");
            }
        }
        IERC20_CCIPBnM(address(tokenL2)).drip(staker);
        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        /// L2: Dispatch Call
        //////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        uint256 amount = 0.0887 ether;
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

        uint256 gasLimit = 730_000;
        // Note: must set gasLimit for deposit + mint EigenAgent: [gas: 724,221]

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
