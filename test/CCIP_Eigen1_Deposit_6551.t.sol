// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IReceiverCCIPMock} from "./mocks/ReceiverCCIPMock.sol";
import {ISenderCCIPMock} from "./mocks/SenderCCIPMock.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {BaseMessengerCCIP} from "../src/BaseMessengerCCIP.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";

import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EigenlayerMsgDecoders} from "../src/utils/EigenlayerMsgDecoders.sol";
import {ClientSigners} from "../script/ClientSigners.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";

// 6551 accounts
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";



contract CCIP_Eigen_Deposit_Tests is Test, EigenlayerMsgDecoders {

    DeployReceiverOnL1Script public deployReceiverOnL1Script;
    DeploySenderOnL2Script public deploySenderOnL2Script;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    ClientSigners public clientSigners;

    IReceiverCCIPMock public receiverContract;
    IRestakingConnector public restakingConnector;
    ISenderCCIPMock public senderContract;

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

    uint256 l2ForkId;
    uint256 ethForkId;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        bobKey = uint256(56789);
        bob = vm.addr(bobKey);

        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
        deploySenderOnL2Script = new DeploySenderOnL2Script();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        clientSigners = new ClientSigners();

        l2ForkId = vm.createFork("basesepolia");
        ethForkId = vm.createSelectFork("ethsepolia");

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
        {
            receiverContract.allowlistSender(deployer, true);
            restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

            IERC20_CCIPBnM(address(tokenL1)).drip(address(receiverContract));
            IERC20_CCIPBnM(address(tokenL1)).drip(bob);

            vm.deal(deployer, 1 ether);
            vm.deal(bob, 1 ether);
        }
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

    function test_CCIP_Eigenlayer_L2_DepositIntoStrategy() public {

        //////////////////////////////////////////////////////
        /// Receiver -> EigenAgent -> Eigenlayer
        //////////////////////////////////////////////////////

        uint256 execNonce = 0;
        bytes memory messageWithSignature;
        {
            bytes memory depositMessage = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
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

        (
            address strategy_,
            address token_,
            uint256 amount_,
            address signer_,
            uint256 expiry_,
            bytes memory signature_
        ) = decodeDepositIntoStrategyMsg(
            abi.encode(string(
                messageWithSignature
            ))
        );

        require(address(strategy_) == address(strategy), "strategy incorrect");
        require(token_ == address(tokenL1), "token incorrect");
        require(amount_ == amount, "amount incorrect");

        require(signer_ == bob, "signer incorrect");
        require(expiry_ == expiry, "expiry incorrect");
        require(signature_.length == 65, "signature length incorrect");

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

    function test_MockSendMessagePayNative_Deposit() public {

        ///////////////////////////////////////////////////
        //// Setup Sender contracts on L2 fork
        ///////////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        (
            ISenderCCIPMock senderContract,
            // ISenderHooks senderHooks
        ) = deploySenderOnL2Script.mockrun();

        vm.deal(address(senderContract), 1 ether);

        vm.startBroadcast(deployer);
        {
            IERC20_CCIPBnM(BaseSepolia.BridgeToken).drip(address(senderContract));
            senderContract.allowlistSender(deployer, true);
        }
        vm.stopBroadcast();

        ///////////////////////////////////////////////////

        uint256 execNonce = 0;
        bytes memory messageWithSignature;
        {
            bytes memory depositMessage = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
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

        // messageId (topic[1]): false as we don't know messageId yet
        vm.expectEmit(false, true, false, false);
        emit BaseMessengerCCIP.MessageSent(
            bytes32(0x0),
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            "dispatched call", // default message
            address(BaseSepolia.BridgeToken), // token to send
            0.1 ether,
            address(0), // native gas for fees
            0
        );
        // event MessageSent(
        //     bytes32 indexed messageId,
        //     uint64 indexed destinationChainSelector,
        //     address receiver,
        //     string text,
        //     address token,
        //     uint256 tokenAmount,
        //     address feeToken,
        //     uint256 fees
        // );
        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature),
            address(BaseSepolia.BridgeToken), // token to send
            0.1 ether, // test sending 0.1e18 tokens
            999_000 // use custom gasLimit for this function
        );
    }
}
