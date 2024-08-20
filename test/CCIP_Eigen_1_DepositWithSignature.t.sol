// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {StrategyManager} from "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";

import {IERC20Minter} from "../src/interfaces/IERC20Minter.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector, EigenlayerDepositWithSignatureParams} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EthSepolia, ArbSepolia} from "../script/Addresses.sol";


contract CCIP_Eigen_DepositWithSignatureTests is Test {

    DeployOnEthScript public deployOnEthScript;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    SignatureUtilsEIP1271 public signatureUtils;
    EigenlayerMsgEncoders public eigenlayerMsgEncoders;

    uint256 public deployerKey;
    address public deployer;

    IReceiverCCIP public receiverContract;
    IRestakingConnector public restakingConnector;
    IERC20_CCIPBnM public erc20Drip; // has drip faucet functions
    IERC20 public token;

    IStrategyManager public strategyManager;
    IPauserRegistry public _pauserRegistry;
    IRewardsCoordinator public _rewardsCoordinator;
    IDelegationManager public delegationManager;
    IStrategy public strategy;

    uint256 public initialReceiverBalance = 5 ether;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deployOnEthScript = new DeployOnEthScript();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        eigenlayerMsgEncoders = new EigenlayerMsgEncoders();
        signatureUtils = new SignatureUtilsEIP1271();

        uint256 arbForkId = vm.createFork("arbsepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

        //// Configure Eigenlayer contracts
        (
            strategy,
            strategyManager,
            , //IStrategyFactory
            _pauserRegistry,
            delegationManager,
            _rewardsCoordinator,
            token
        ) = deployMockEigenlayerContractsScript.deployEigenlayerContracts(false);

        //// Configure CCIP contracts
        (
            receiverContract,
            restakingConnector
        ) = deployOnEthScript.run();

        erc20Drip = IERC20_CCIPBnM(address(token));

        vm.startBroadcast(deployerKey);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);
        // fund receiver with tokens from CCIP bridge: EVM2EVMOffRamp contract
        erc20Drip.drip(address(receiverContract));
        erc20Drip.drip(address(receiverContract));

        receiverContract.allowlistSender(deployer, true);

        vm.stopBroadcast();
    }


    function test_CCIP_Eigenlayer_DepositIntoStrategyWithSignature() public {

        uint256 amount = 0.0077 ether;
        address staker = deployer;
        uint256 expiry = block.timestamp + 1 days;
        uint256 nonce = 0;
        bytes32 domainSeparator = signatureUtils.getDomainSeparator(address(strategyManager), block.chainid);
        (
            bytes memory signature,
            bytes32 digestHash
        ) = signatureUtils.createEigenlayerDepositSignature(
            deployerKey,
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
            messageId: bytes32(0xffffffffffffffff9999999999999999eeeeeeeeeeeeeeee8888888888888888),
            sourceChainSelector: ArbSepolia.ChainSelector, // Arb Sepolia source chain selector
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
            amount,
            0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c
        );

        /////////////////////////////////////
        //// Send message from CCIP to Eigenlayer
        /////////////////////////////////////
        vm.startBroadcast(EthSepolia.Router); // simulate router calling receiverContract on L1
        receiverContract.mockCCIPReceive(any2EvmMessage);

        uint256 receiverBalance = token.balanceOf(address(receiverContract));
        uint256 valueOfShares = strategy.userUnderlying(address(deployer));

        require(valueOfShares == amount, "valueofShares incorrect");
        require(strategyManager.stakerStrategyShares(staker, strategy) == amount, "stakerStrategyShares incorrect");

        vm.stopBroadcast();
    }

    function test_Eigenlayer_DepositIntoStrategyWithSignature() public {

        address staker = deployer;
        uint256 expiry = block.timestamp + 1 days;
        uint256 amount = 1 ether;
        uint256 nonce = 0;
        bytes32 domainSeparator = signatureUtils.getDomainSeparator(address(strategyManager), block.chainid);

        vm.startBroadcast(deployerKey);
        erc20Drip.drip(staker);
        erc20Drip.approve(address(strategyManager), amount);

        (
            bytes memory signature,
            bytes32 digestHash
        ) = signatureUtils.createEigenlayerDepositSignature(
            deployerKey,
            strategy,
            token,
            amount,
            staker,
            nonce,
            expiry,
            domainSeparator
        );

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
}
