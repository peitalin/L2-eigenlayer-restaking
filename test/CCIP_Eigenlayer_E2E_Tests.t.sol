// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {IRouterClient, WETH9, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IMockERC20} from "../src/IMockERC20.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/IReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector, EigenlayerDepositWithSignatureParams} from "../src/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";

import {StrategyManager} from "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";
import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";


contract CCIP_Eigenlayer_E2E_Tests is Test {

    DeployOnEthScript public deployOnEthScript;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    SignatureUtilsEIP1271 public signatureUtils;
    EigenlayerMsgEncoders public eigenlayerMsgEncoders;

    uint256 public deployerKey;
    address public deployer;

    IReceiverCCIP public receiverContract;
    IRestakingConnector public restakingConnector;
    IMockERC20 public mockERC20; // has admin mint/burn functions
    IERC20 public token;

    IStrategyManager public strategyManager;
    IPauserRegistry public _pauserRegistry;
    IRewardsCoordinator public _rewardsCoordinator;
    IDelegationManager public delegationManager;
    IStrategy public strategy;

    // Initial CCIP Receiver balance
    uint256 public initialReceiverBalance = 5 ether;
    uint64 public sourceChainSelector = 3478487238524512106;
    address public router = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        eigenlayerMsgEncoders = new EigenlayerMsgEncoders();
        signatureUtils = new SignatureUtilsEIP1271();
        deployOnEthScript = new DeployOnEthScript();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        //// Configure CCIP contracts
        (
            receiverContract,
            restakingConnector
        ) = deployOnEthScript.run();

        //// Configure Eigenlayer contracts
        (
            strategyManager,
            _pauserRegistry,
            _rewardsCoordinator,
            delegationManager,
            strategy,
            token
        ) = deployMockEigenlayerContractsScript.run();

        mockERC20 = IMockERC20(address(token));

        vm.startBroadcast(deployerKey);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);
        // fund receiver with tokens from CCIP bridge: EVM2EVMOffRamp contract
        mockERC20.mint(address(receiverContract), initialReceiverBalance);
        vm.stopBroadcast();
    }


    function test_Eigenlayer_CCIP_E2E_DepositIntoStrategyWithSignature() public {

        vm.startBroadcast(deployerKey);
        receiverContract.allowlistSender(deployer, true);
        vm.stopBroadcast();

        uint256 amount = 0.0077 ether;
        address staker = deployer;
        uint256 expiry = block.timestamp + 1 days;
        uint256 nonce = 0;
        bytes32 domainSeparator = signatureUtils.getDomainSeparator(address(strategyManager), block.chainid);
        (bytes memory signature, bytes32 digestHash) = createSignature(
            strategy,
            token,
            amount,
            staker,
            nonce,
            expiry,
            domainSeparator
        );

        signatureUtils.checkSignature_EIP1271(staker, digestHash, signature);

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(token), // CCIP-BnM token address on Eth Sepolia.
            amount: amount
        });

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0x598fff8ee56c84a5d8793c1ac075501711392720209f72ae3cfb445d4116d272),
            sourceChainSelector: sourceChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
            data: abi.encode(string(
                eigenlayerMsgEncoders.encodeDepositIntoStrategyWithSignatureMsg(
                    address(strategy),
                    address(token),
                    amount,
                    staker,
                    expiry,
                    signature
                )
            )), // CCIP abi.encodes a string message when sending
            destTokenAmounts: destTokenAmounts // Tokens and their amounts in their destination chain representation.
        });

        //// Test emitted events
        //// (first 3 args: check indexed topics), (4th arg = true = check data)
        vm.expectEmit(true, true, true, true);
        emit EigenlayerDepositWithSignatureParams(
            0x32e89ace,
            amount,
            0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c
        );

        /////////////////////////////////////
        //// Send message from CCIP to Eigenlayer
        /////////////////////////////////////
        vm.startBroadcast(router); // simulate router sending message to receiverContract on L1
        receiverContract.mockCCIPReceive(any2EvmMessage);

        uint256 receiverBalance = token.balanceOf(address(receiverContract));
        uint256 valueOfShares = strategy.userUnderlying(address(deployer));

        require(valueOfShares == amount, "valueofShares incorrect");
        console.log("receiver balance:", receiverBalance);
        console.log("receiver shares value:", valueOfShares);

        vm.stopBroadcast();
    }

    function test_Eigenlayer_DepositIntoStrategyWithSignature() public {

        address staker = deployer;
        uint256 expiry = block.timestamp + 1 days;
        uint256 amount = 1 ether;
        uint256 nonce = 0;
        bytes32 domainSeparator = signatureUtils.getDomainSeparator(address(strategyManager), block.chainid);

        vm.startBroadcast(deployerKey);
        mockERC20.mint(staker, amount);
        mockERC20.approve(address(strategyManager), amount);

        (bytes memory signature, bytes32 digestHash) = createSignature(
            strategy,
            token,
            amount,
            staker,
            nonce,
            expiry,
            domainSeparator
        );

        console.log("strategy:", address(strategy));
        console.log("token:", address(token));

        signatureUtils.checkSignature_EIP1271(staker, digestHash, signature);

        strategyManager.depositIntoStrategyWithSignature(
            strategy,
            token,
            amount,
            staker,
            expiry,
            signature
        );

        require(strategyManager.stakerStrategyShares(staker, strategy) == 1 ether, "deposit failed");

        vm.stopBroadcast();
    }

    function test_Eigenlayer_DelegateToOperator() public {
        // DelegationManager.undelegate
        // DelegationManager.queueWithdrawals
        // DelegationManager.completeQueuedWithdrawal
        // DelegationManager.completeQueuedWithdrawals
    }

    function test_Eigenlayer_UndelegateFromOperator() public {

    }

    function test_Eigenlayer_QueueWithdrawal() public {

    }

    function test_Eigenlayer_QueueWithdrawals() public {

    }

    function createSignature(
        IStrategy _strategy,
        IERC20 _token,
        uint256 amount,
        address staker,
        uint256 nonce,
        uint256 expiry,
        bytes32 domainSeparator
    ) public returns (bytes memory, bytes32) {

        bytes32 digestHash = signatureUtils.createEigenlayerDepositDigest(
            _strategy,
            _token,
            amount,
            staker,
            nonce,
            expiry,
            domainSeparator
        );
        // generate ECDSA signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        // r,s,v packed into 65byte signature: 32 + 32 + 1.
        // the order of r,s,v differs from the above
        return (signature, digestHash);
    }
}
