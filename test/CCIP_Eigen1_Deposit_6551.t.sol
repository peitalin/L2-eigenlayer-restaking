// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {IReceiverCCIPMock} from "./mocks/ReceiverCCIPMock.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";

import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {ClientSigners} from "../script/ClientSigners.sol";
import {BaseSepolia} from "../script/Addresses.sol";

// 6551 accounts
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";



contract CCIP_Eigen_Deposit_6551Tests is Test {

    DeployReceiverOnL1Script public deployReceiverOnL1Script;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    ClientSigners public clientSigners;

    IReceiverCCIPMock public receiverContract;
    IRestakingConnector public restakingConnector;

    IAgentFactory public agentFactory;
    EigenAgentOwner721 public eigenAgentOwnerNft;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IERC20 public tokenL1;
    IStrategy public strategy;

    uint256 deployerKey;
    address deployer;
    uint256 bobKey;
    address bob;
    // call params
    uint256 expiry;
    uint256 amount;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        bobKey = uint256(56789);
        bob = vm.addr(bobKey);
        vm.deal(bob, 1 ether);

        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        clientSigners = new ClientSigners();

        // uint256 l2ForkId = vm.createFork("basesepolia");
        vm.createSelectFork("ethsepolia");

        //// Configure Eigenlayer contracts
        (
            strategy,
            strategyManager,
            , // IStrategyFactory
            , // pauserRegistry
            delegationManager,
            , // rewardsCoordinator
            tokenL1
        ) = deployMockEigenlayerContractsScript.deployEigenlayerContracts(false);

        //// Configure CCIP contracts and ERC6551 EigenAgents
        (
            receiverContract,
            restakingConnector,
            agentFactory
        ) = deployReceiverOnL1Script.mockrun();

        //// allowlist deployer and mint initial balances
        vm.startBroadcast(deployerKey);

        receiverContract.allowlistSender(deployer, true);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

        IERC20_CCIPBnM(address(tokenL1)).drip(address(receiverContract));
        IERC20_CCIPBnM(address(tokenL1)).drip(bob);

        vm.stopBroadcast();

        amount = 0.0028 ether;
        expiry = block.timestamp + 1 days;
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_CCIP_Eigenlayer_DepositIntoStrategy6551() public {

        //////////////////////////////////////////////////////
        /// Receiver -> EigenAgent -> Eigenlayer
        //////////////////////////////////////////////////////

        uint256 execNonce = 0;
        bytes memory depositMessage;
        bytes memory messageWithSignature;
        {
            depositMessage = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = clientSigners.signMessageForEigenAgentExecution(
                bobKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager), // StrategyManager to approve + deposit
                depositMessage,
                execNonce,
                expiry
            );
        }

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1), // CCIP-BnM token address on Eth Sepolia.
            amount: amount
        });
        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0x0),
            sourceChainSelector: BaseSepolia.ChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
            destTokenAmounts: destTokenAmounts, // Tokens and their amounts in their destination chain representation.
            data: abi.encode(string(
                messageWithSignature
            )) // CCIP abi.encodes a string message when sending
        });

        /////////////////////////////////////
        //// Mock send message to CCIP -> EigenAgent -> Eigenlayer
        /////////////////////////////////////
        vm.startBroadcast(deployerKey);
        receiverContract.mockCCIPReceive(any2EvmMessage);

        IEigenAgent6551 eigenAgent = agentFactory.getEigenAgent(bob);

        uint256 valueOfShares = strategy.userUnderlying(address(eigenAgent));
        require(amount == valueOfShares, "valueofShares incorrect");
        require(
            amount == strategyManager.stakerStrategyShares(address(eigenAgent), strategy),
            "Bob's EigenAgent stakerStrategyShares should equal deposited amount"
        );
        vm.stopBroadcast();
    }

}
