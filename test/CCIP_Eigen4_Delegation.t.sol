// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {IERC20Minter} from "../src/interfaces/IERC20Minter.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {IReceiverCCIPMock} from "./mocks/ReceiverCCIPMock.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderCCIPMock} from "./mocks/SenderCCIPMock.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";

import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";
import {ClientSigners} from "../script/ClientSigners.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";


contract CCIP_Eigen_DelegationTests is Test {

    DeployReceiverOnL1Script public deployReceiverOnL1Script;
    DeploySenderOnL2Script public deployOnL2Script;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    ClientSigners public clientSigners;

    IReceiverCCIPMock public receiverContract;
    ISenderCCIPMock public senderContract;
    IRestakingConnector public restakingConnector;
    IAgentFactory public agentFactory;

    IStrategyManager public strategyManager;
    IPauserRegistry public _pauserRegistry;
    IRewardsCoordinator public _rewardsCoordinator;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    IERC20 public tokenL1;

    uint256 deployerKey;
    address deployer;
    IEigenAgent6551 eigenAgent;

    uint256 operatorKey;
    address operator;
    uint256 amount = 0.0091 ether;

    uint256 l2ForkId;
    uint256 ethForkId;

    function setUp() public {

        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
        deployOnL2Script = new DeploySenderOnL2Script();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        clientSigners = new ClientSigners();

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        operatorKey = vm.envUint("OPERATOR_KEY");
        operator = vm.addr(operatorKey);

        l2ForkId = vm.createFork("basesepolia");        // 0
        ethForkId = vm.createSelectFork("ethsepolia"); // 1

        (
            strategy,
            strategyManager,
            , //IStrategyFactory
            _pauserRegistry,
            delegationManager,
            _rewardsCoordinator,
            tokenL1
        ) = deployMockEigenlayerContractsScript.deployEigenlayerContracts(false);

        //////////// Arb Sepolia ////////////
        vm.selectFork(l2ForkId);
        senderContract = deployOnL2Script.mockrun();


        //////////// Eth Sepolia ////////////
        vm.selectFork(ethForkId);
        (
            receiverContract,
            restakingConnector,
            agentFactory
        ) = deployReceiverOnL1Script.mockrun();


        //////////// Arb Sepolia ////////////
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);
        // allow L2 sender contract to receive tokens back from L1
        senderContract.allowlistSourceChain(EthSepolia.ChainSelector, true);
        senderContract.allowlistSender(address(receiverContract), true);
        senderContract.allowlistSender(deployer, true);
        // fund L2 sender with gas and CCIP-BnM tokens
        vm.deal(address(senderContract), 1 ether); // fund for gas
        if (block.chainid == BaseSepolia.ChainId) {
            // drip() using CCIP's BnM faucet if forking from Arb Sepolia
            IERC20_CCIPBnM(BaseSepolia.BridgeToken).drip(address(senderContract));
        } else {
            // mint() if we deployed our own Mock ERC20
            IERC20Minter(BaseSepolia.BridgeToken).mint(address(senderContract), 1 ether);
        }
        vm.stopBroadcast();


        //////////// Eth Sepolia ////////////
        vm.selectFork(ethForkId);

        vm.startBroadcast(deployerKey);
        receiverContract.allowlistSender(deployer, true);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

        // fund L1 receiver with gas and CCIP-BnM tokens
        vm.deal(address(receiverContract), 1 ether); // fund for gas
        if (block.chainid == EthSepolia.ChainId) {
            // drip() using CCIP's BnM faucet if forking from Eth Sepolia
            IERC20_CCIPBnM(address(tokenL1)).drip(address(receiverContract));
        } else {
            // mint() if we deployed our own Mock ERC20
            IERC20Minter(address(tokenL1)).mint(address(receiverContract), 1 ether);
        }

        vm.stopBroadcast();

        /////////////////////////////////////
        //// Register Operators
        /////////////////////////////////////

        vm.startBroadcast(operatorKey);
        IDelegationManager.OperatorDetails memory registeringOperatorDetails =
            IDelegationManager.OperatorDetails({
                __deprecated_earningsReceiver: vm.addr(0xb0b),
                delegationApprover: operator,
                stakerOptOutWindowBlocks: 4
            });

        string memory metadataURI = "some operator";
        delegationManager.registerAsOperator(registeringOperatorDetails, metadataURI);

        require(delegationManager.isOperator(operator), "operator not set");
        vm.stopBroadcast();

        /////////////////////////////////////
        //// Deposit with EigenAgent
        /////////////////////////////////////

        vm.startBroadcast(deployerKey);

        uint256 expiry = block.timestamp + 1 days;
        uint256 execNonce0 = 0; // no eigenAgent yet, execNonce is 0

        bytes memory depositMessage;
        bytes memory messageWithSignature_D;
        {
            depositMessage = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_D = clientSigners.signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager),
                depositMessage,
                execNonce0,
                expiry
            );
        }

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1), // CCIP-BnM token address on Eth Sepolia.
            amount: amount
        });

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: destTokenAmounts,
                data: abi.encode(string(
                    messageWithSignature_D
                )) // CCIP abi.encodes a string message when sending
            })
        );

        eigenAgent = agentFactory.getEigenAgent(deployer);

        vm.stopBroadcast();
    }


    function test_Eigenlayer_DelegateTo() public {

        // Operator Approver signs the delegateTo call
        bytes32 approverSalt = bytes32(uint256(222222));
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;
        {
            uint256 sig1_expiry = block.timestamp + 1 hours;
            bytes32 digestHash1 = clientSigners.calculateDelegationApprovalDigestHash(
                address(eigenAgent), // staker == msg.sender == eigenAgent from Eigenlayer's perspective
                operator, // operator
                operator, // _delegationApprover,
                approverSalt,
                sig1_expiry,
                address(delegationManager), // delegationManagerAddr
                block.chainid
            );

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorKey, digestHash1);
            bytes memory signature1 = abi.encodePacked(r, s, v);
            approverSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature1,
                expiry: sig1_expiry
            });
        }

        // append user signature for EigenAgent execution
        bytes memory messageWithSignature_DT;
        {
            uint256 execNonce1 = 1;
            uint256 expiry2 = block.timestamp + 1 hours;

            bytes memory delegateToMessage = EigenlayerMsgEncoders.encodeDelegateTo(
                operator,
                approverSignatureAndExpiry,
                approverSalt
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_DT = clientSigners.signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(delegationManager), // DelegationManager.delegateTo()
                delegateToMessage,
                execNonce1,
                expiry2
            );
        }

        vm.expectEmit(true, true, false, false);
        emit IDelegationManager.StakerDelegated(address(eigenAgent), operator);

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging any tokens
                data: abi.encode(string(
                    messageWithSignature_DT
                ))
            })
        );

        ///////////////////////////////////////
        ///// Undelegate
        ///////////////////////////////////////
        vm.warp(block.timestamp + 1 hours);
        vm.roll(block.number + (3600 / 12));

        bytes memory messageWithSignature_UD;
        {
            uint256 execNonce2 = 2;
            uint256 expiry = block.timestamp + 1 hours;
            bytes memory message_UD = EigenlayerMsgEncoders.encodeUndelegateMsg(
                address(eigenAgent)
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_UD = clientSigners.signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(delegationManager), // DelegationManager
                message_UD,
                execNonce2,
                expiry
            );
        }

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging any tokens
                data: abi.encode(string(
                    messageWithSignature_UD
                ))
            })
        );

    }

    function test_Eigenlayer_Undelegate() public {
        // refactor above test into this one
    }

}
