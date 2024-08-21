// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
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
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {EigenlayerDepositWithSignatureParams} from "../src/interfaces/IEigenlayerMsgDecoders.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";
import {DeployOnL2Script} from "../script/2_deployOnL2.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";


contract CCIP_Eigen_QueueWithdrawalsTests is Test {

    DeployOnEthScript public deployOnEthScript;
    DeployOnL2Script public deployOnL2Script;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    SignatureUtilsEIP1271 public signatureUtils;

    uint256 public deployerKey;
    address public deployer;

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    IERC20 public token;

    IStrategyManager public strategyManager;
    IPauserRegistry public _pauserRegistry;
    IRewardsCoordinator public _rewardsCoordinator;
    IDelegationManager public delegationManager;
    IStrategy public strategy;

    uint256 public stakerShares;
    uint256 public initialReceiverBalance = 5 ether;
    uint256 public amountToStake = 0.0091 ether;
    address public staker;

    uint256 l2ForkId;
    uint256 ethForkId;
    uint256 localForkId;
    bool isTest;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deployOnEthScript = new DeployOnEthScript();
        deployOnL2Script = new DeployOnL2Script();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        signatureUtils = new SignatureUtilsEIP1271();

        (
            strategy,
            strategyManager,
            , //IStrategyFactory
            _pauserRegistry,
            delegationManager,
            _rewardsCoordinator,
            token
        ) = deployMockEigenlayerContractsScript.deployEigenlayerContracts(false);

        staker = deployer;
        vm.deal(deployer, 1 ether);
        vm.deal(address(senderContract), 1.333 ether); // fund for gas
        vm.deal(address(receiverContract), 1.111 ether); // fund for gas

        senderContract = deployOnL2Script.run();

        (receiverContract, restakingConnector) = deployOnEthScript.run();

        //////////// Arb Sepolia ////////////
        vm.startBroadcast(deployerKey);
        // allow L2 sender contract to receive tokens back from L1
        senderContract.allowlistSourceChain(EthSepolia.ChainSelector, true);
        senderContract.allowlistSender(address(receiverContract), true);
        senderContract.allowlistSender(deployer, true);
        // mint() if we deployed our own Mock ERC20
        IERC20Minter(address(token)).mint(address(senderContract), 5 ether);
        vm.stopBroadcast();

        //////////// Eth Sepolia ////////////
        vm.startBroadcast(deployerKey);
        receiverContract.allowlistSender(deployer, true);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);
        // mint() if we deployed our own Mock ERC20
        IERC20Minter(address(token)).mint(address(receiverContract), initialReceiverBalance);
        vm.stopBroadcast();

        /////////////////////////////////////
        //// ETH: Mock deposits on Eigenlayer
        /////////////////////////////////////
        vm.startBroadcast(address(receiverContract)); // simulate router sending receiver message on L1
        Client.Any2EVMMessage memory any2EvmMessage = makeCCIPEigenlayerMsg_DepositWithSignature(
            amountToStake,
            staker,
            block.timestamp + 1 hours
        );
        receiverContract.mockCCIPReceive(any2EvmMessage);

        stakerShares = strategyManager.stakerStrategyShares(staker, strategy);
        uint256 receiverShares = strategyManager.stakerStrategyShares(address(receiverContract), strategy);

        require(stakerShares == amountToStake, "stakerStrategyShares incorrect");
        require(receiverShares == 0, "receiverContract should not hold any shares");

        vm.stopBroadcast();
    }


    function test_Eigenlayer_Revert_QueueWithdrawal() public {

        vm.startBroadcast(deployerKey);

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = stakerShares;

        IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal =
            IDelegationManager.QueuedWithdrawalParams({
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw,
                withdrawer: msg.sender
            });

        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams =
            new IDelegationManager.QueuedWithdrawalParams[](1);
        queuedWithdrawalParams[0] = queuedWithdrawal;

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(token),
            amount: amountToStake
        });

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0xffffffffffffffff9999999999999999eeeeeeeeeeeeeeee8888888888888888),
            sourceChainSelector: BaseSepolia.ChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(address(deployer)), // bytes: abi.decode(sender) if coming from an EVM chain.
            data: abi.encode(string(
                EigenlayerMsgEncoders.encodeQueueWithdrawalMsg(
                    queuedWithdrawalParams
                )
            )), // CCIP abi.encodes a string message when sending
            destTokenAmounts: destTokenAmounts // Tokens and their amounts in their destination chain representation.
        });

        // msg.sender must be staker, so it's impossible for the CCIP bridge contract to conduct
        // third party queueWithdrawals for a staker.
        // We would need a queueWithdrawalWithSignature feature:
        // https://github.com/Layr-Labs/eigenlayer-contracts/pull/676
        vm.expectRevert("DelegationManager.queueWithdrawal: withdrawer must be staker");
        receiverContract.mockCCIPReceive(any2EvmMessage);

        vm.stopBroadcast();
    }


    function test_Eigenlayer_QueueWithdrawalsWithSignature() public {

        vm.startBroadcast(address(receiverContract));

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = stakerShares;

        uint256 expiry = block.timestamp + 1 hours;
        address withdrawer = address(receiverContract);
        uint256 stakerNonce = delegationManager.cumulativeWithdrawalsQueued(staker);
        // startBlock: calculated on the block when queueWithdrawals was called.
        uint32 startBlock = uint32(block.number); // needed to CompleteWithdrawals

        bytes32 digestHash = signatureUtils.calculateQueueWithdrawalDigestHash(
            staker,
            strategiesToWithdraw,
            sharesToWithdraw,
            stakerNonce,
            expiry,
            address(delegationManager),
            block.chainid
        );

        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash);
            signature = abi.encodePacked(r, s, v);
        }

        signatureUtils.checkSignature_EIP1271(staker, digestHash, signature);

        /////////////////////////////////////////////////////////////////
        //// Queue Withdrawals via CCIP
        /////////////////////////////////////////////////////////////////
        receiverContract.mockCCIPReceive(
            makeCCIPEigenlayerMsg_QueueWithdrawalsWithSignature(
                strategiesToWithdraw,
                sharesToWithdraw,
                withdrawer,
                staker,
                signature,
                expiry
            )
        );

        console.log("balanceOf(receiverContract) before:", token.balanceOf(address(receiverContract)));
        require(
            token.balanceOf(address(receiverContract)) == initialReceiverBalance - amountToStake,
            "balance should be: initialReceiverBalance - amountToStake"
        );

        vm.stopBroadcast();
    }


    function makeCCIPEigenlayerMsg_QueueWithdrawalsWithSignature(
            IStrategy[] memory _strategiesToWithdraw,
            uint256[] memory _sharesToWithdraw,
            address _withdrawer,
            address _staker,
            bytes memory _signature,
            uint256 _expiry
    ) public view returns (Client.Any2EVMMessage memory) {

        IDelegationManager.QueuedWithdrawalWithSignatureParams memory queuedWithdrawalWithSig;
        queuedWithdrawalWithSig = IDelegationManager.QueuedWithdrawalWithSignatureParams({
            strategies: _strategiesToWithdraw,
            shares: _sharesToWithdraw,
            withdrawer: _withdrawer,
            staker: _staker,
            signature: _signature,
            expiry: _expiry
        });

        IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalWithSigArray;
        queuedWithdrawalWithSigArray = new IDelegationManager.QueuedWithdrawalWithSignatureParams[](1);
        queuedWithdrawalWithSigArray[0] = queuedWithdrawalWithSig;

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(token),
            amount: 0 // not bridging, just sending CCIP message
        });

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0xffffffffffffffff9999999999999999eeeeeeeeeeeeeeee8888888888888888),
            sourceChainSelector: BaseSepolia.ChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(address(deployer)), // bytes: abi.decode(sender) if coming from an EVM chain.
            data: abi.encode(string(
                EigenlayerMsgEncoders.encodeQueueWithdrawalsWithSignatureMsg(
                    queuedWithdrawalWithSigArray
                )
            )), // CCIP abi.encodes a string message when sending
            destTokenAmounts: destTokenAmounts // Tokens and their amounts in their destination chain representation.
        });

        return any2EvmMessage;
    }

    function makeCCIPEigenlayerMsg_DepositWithSignature(
        uint256 _amount,
        address _staker,
        uint256 expiry
    ) public view returns (Client.Any2EVMMessage memory) {

        uint256 nonce = 0; // in production retrieve on StrategyManager on L1
        bytes32 domainSeparator = signatureUtils.getDomainSeparator(address(strategyManager), block.chainid);

        (
            bytes memory signature,
            bytes32 digestHash
        ) = signatureUtils.createEigenlayerDepositSignature(
            deployerKey,
            strategy,
            token,
            _amount,
            _staker,
            nonce,
            expiry,
            domainSeparator
        );

        signatureUtils.checkSignature_EIP1271(_staker, digestHash, signature);

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(token),
            amount: _amount
        });

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0xffffffffffffffff9999999999999999eeeeeeeeeeeeeeee8888888888888888),
            sourceChainSelector: BaseSepolia.ChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
            data: abi.encode(string(
                EigenlayerMsgEncoders.encodeDepositIntoStrategyWithSignatureMsg(
                    address(strategy),
                    address(token),
                    _amount,
                    _staker,
                    expiry,
                    signature
                )
            )), // CCIP abi.encodes a string message when sending
            destTokenAmounts: destTokenAmounts // Tokens and their amounts in their destination chain representation.
        });

        return any2EvmMessage;
    }

}
