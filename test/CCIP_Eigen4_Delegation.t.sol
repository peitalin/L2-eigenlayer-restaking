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

    uint256 stakerShares;
    uint256 initialReceiverBalance = 1 ether;
    uint256 amountToStake = 0.0091 ether;
    address staker;
    uint256 operatorKey;
    address operator;

    uint256 l2ForkId;
    uint256 ethForkId;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
        deployOnL2Script = new DeploySenderOnL2Script();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        clientSigners = new ClientSigners();

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

        staker = deployer;
        operatorKey = vm.envUint("OPERATOR_KEY");
        operator = vm.addr(operatorKey);

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
        vm.deal(address(senderContract), 1.333 ether); // fund for gas
        if (block.chainid == BaseSepolia.ChainId) {
            // drip() using CCIP's BnM faucet if forking from Arb Sepolia
            for (uint256 i = 0; i < 5; ++i) {
                IERC20_CCIPBnM(BaseSepolia.BridgeToken).drip(address(senderContract));
                // each drip() gives you 1e18 coin
            }
        } else {
            // mint() if we deployed our own Mock ERC20
            IERC20Minter(BaseSepolia.BridgeToken).mint(address(senderContract), 5 ether);
        }
        vm.stopBroadcast();


        //////////// Eth Sepolia ////////////
        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);
        receiverContract.allowlistSender(deployer, true);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);
        console.log("block.chainid", block.chainid);

        // fund L1 receiver with gas and CCIP-BnM tokens
        vm.deal(address(receiverContract), 1.111 ether); // fund for gas
        if (block.chainid == 11155111) {
            // drip() using CCIP's BnM faucet if forking from Eth Sepolia
            for (uint256 i = 0; i < 5; ++i) {
                IERC20_CCIPBnM(address(tokenL1)).drip(address(receiverContract));
                // each drip() gives you 1e18 coin
            }
            initialReceiverBalance = IERC20_CCIPBnM(address(tokenL1)).balanceOf(address(receiverContract));
            // set initialReceiverBalancer for tests
        } else {
            // mint() if we deployed our own Mock ERC20
            IERC20Minter(address(tokenL1)).mint(address(receiverContract), initialReceiverBalance);
        }

        vm.stopBroadcast();

        // /////////////////////////////////////
        // //// ETH: Mock deposits on Eigenlayer
        // vm.selectFork(ethForkId);
        // /////////////////////////////////////


        // register Operator, to test delegation
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
    }


    function test_Eigenlayer_DelegateTo() public {

        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry;
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;

        bytes32 approverSalt = bytes32(uint256(22));

        bytes memory signature1;
        bytes memory signature2;
        {
            uint256 sig1_expiry = block.timestamp + 1 hours;
            uint256 sig2_expiry = block.timestamp + 2 hours;

            bytes32 digestHash1 = clientSigners.calculateStakerDelegationDigestHash(
                staker,
                0,  // nonce
                operator,
                sig1_expiry,
                address(delegationManager),
                block.chainid
            );
            bytes32 digestHash2 = clientSigners.calculateDelegationApprovalDigestHash(
                staker,
                operator,
                operator, // _delegationApprover,
                approverSalt,
                sig2_expiry,
                address(delegationManager), // delegationManagerAddr
                block.chainid
            );

            (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(deployerKey, digestHash1);
            signature1 = abi.encodePacked(r1, s1, v1);
            stakerSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature1,
                expiry: sig1_expiry
            });

            (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(operatorKey, digestHash2);
            signature2 = abi.encodePacked(r2, s2, v2);
            approverSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature2,
                expiry: sig2_expiry
            });
        }

        bytes memory message = EigenlayerMsgEncoders.encodeDelegateToBySignature(
            staker,
            operator,
            stakerSignatureAndExpiry,
            approverSignatureAndExpiry,
            approverSalt
        );

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(uint256(9999)),
            sourceChainSelector: BaseSepolia.ChainSelector,
            sender: abi.encode(deployer),
            destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging any tokens
            data: abi.encode(string(
                message
            ))
        });

        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    function test_Eigenlayer_Undelegate() public {
        // DelegationManager.undelegate
    }


}
