// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin-v47-contracts/token/ERC20/IERC20.sol";
import {IBurnMintERC20} from "@chainlink/shared/token/ERC20/IBurnMintERC20.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {EthHolesky} from "./Addresses.sol";
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
        // User already has an EigenAgent, use script 5b_depositIntoStrategy for lower cost.
        //
        // If user does not have an EigenAgent yet, we need to predict the address of the
        // EigenAgent to use in the message signature that the EigenAgent (yet to be minted) will execute.
        address predictedEigenAgentAddr = agentFactory.predictEigenAgentAddress(staker, 0);

        //////////////////////////////////////////////////////
        /// L2: Fund staker account
        //////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);
        if (isTest) {
            vm.deal(staker, 1 ether);
            (bool success, ) = staker.call{value: 0.5 ether}("");
        } else {
            if (staker.balance < 0.04 ether) {
                (bool success, ) = staker.call{value: 0.03 ether}("");
            }
        }

        if (tokenL2.balanceOf(deployer) < 1 ether) {
            IBurnMintERC20(address(tokenL2)).mint(deployer, 1 ether);
        }
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
            predictedEigenAgentAddr,
            EthHolesky.ChainId, // destination chainid where EigenAgent lives
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

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL2),
            amount: amount
        });

        uint256 routerFees = getRouterFeesL2(
            address(receiverContract),
            string(messageWithSignature),
            tokenAmounts,
            gasLimit
        );

        vm.startBroadcast(stakerKey);
        {
            if (staker != deployer) {
                tokenL2.transfer(staker, amount);
            }
            tokenL2.approve(address(senderContract), amount);

            senderContract.sendMessagePayNative{value: routerFees}(
                EthHolesky.ChainSelector, // destination chain
                address(receiverContract),
                string(messageWithSignature),
                tokenAmounts,
                gasLimit // use default gasLimit if 0
            );
        }
        vm.stopBroadcast();
    }
}
