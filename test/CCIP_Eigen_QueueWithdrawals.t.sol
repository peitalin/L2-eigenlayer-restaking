// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {IERC20Minter} from "../src/interfaces/IERC20Minter.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector, EigenlayerDepositWithSignatureParams} from "../src/interfaces/IRestakingConnector.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";
import {DeployOnArbScript} from "../script/2_deployOnArb.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EthSepolia, ArbSepolia} from "../script/Addresses.sol";


contract CCIP_Eigen_QueueWithdrawals is Test {

    DeployOnEthScript public deployOnEthScript;
    DeployOnArbScript public deployOnArbScript;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    SignatureUtilsEIP1271 public signatureUtils;
    EigenlayerMsgEncoders public eigenlayerMsgEncoders;

    uint256 public deployerKey;
    address public deployer;

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    IERC20Minter public erc20Minter; // has admin mint/burn functions
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

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deployOnEthScript = new DeployOnEthScript();
        deployOnArbScript = new DeployOnArbScript();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        eigenlayerMsgEncoders = new EigenlayerMsgEncoders();
        signatureUtils = new SignatureUtilsEIP1271();

        //// Configure CCIP contracts
        (
            receiverContract,
            restakingConnector
        ) = deployOnEthScript.run();

        senderContract = deployOnArbScript.run();

        //// Configure Eigenlayer contracts
        (
            strategyManager,
            _pauserRegistry,
            _rewardsCoordinator,
            delegationManager,
            strategy,
            token
        ) = deployMockEigenlayerContractsScript.run();

        erc20Minter = IERC20Minter(address(token));

        staker = deployer;

        //////////////////////////////////////
        // Broadcast
        //////////////////////////////////////
        vm.startBroadcast(deployerKey);

        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);
        // fund receiver with tokens from CCIP bridge: EVM2EVMOffRamp contract
        erc20Minter.mint(address(receiverContract), initialReceiverBalance);
        receiverContract.allowlistSender(deployer, true);
        vm.stopBroadcast();

        /////////////////////////////////////
        //// Setup deposits on Eigenlayer
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

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = stakerShares;
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
            sourceChainSelector: ArbSepolia.ChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(address(deployer)), // bytes: abi.decode(sender) if coming from an EVM chain.
            data: abi.encode(string(
                eigenlayerMsgEncoders.encodeQueueWithdrawalMsg(
                    queuedWithdrawalParams
                )
            )), // CCIP abi.encodes a string message when sending
            destTokenAmounts: destTokenAmounts // Tokens and their amounts in their destination chain representation.
        });

        // msg.sender must be staker, so it's impossible for the CCIP bridge contract to conduct
        // third party queueWithdrawals for a staker.
        // We would need a queueWithdrawalWithSignature feature:
        // https://github.com/Layr-Labs/eigenlayer-contracts/pull/676
        vm.expectRevert("queueWithdrawal: withdrawer must be staker");
        receiverContract.mockCCIPReceive(any2EvmMessage);

        vm.stopBroadcast();
    }


    function test_Eigenlayer_QueueWithdrawalsWithSignature() public {
        // Note: This test needs the queueWithdrawalWithSignature feature:
        // https://github.com/Layr-Labs/eigenlayer-contracts/pull/676
        vm.startBroadcast(address(receiverContract));

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = stakerShares;

        uint256 expiry = block.timestamp + 6 hours;
        address withdrawer = address(receiverContract);
        uint256 stakerNonce = delegationManager.cumulativeWithdrawalsQueued(staker);
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
        ////// Queue Withdrawals via CCIP
        /////////////////////////////////////////////////////////////////

        (
            IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalWithSigParams,
            Client.Any2EVMMessage memory any2EvmMessage1
        ) = makeCCIPEigenlayerMsg_QueueWithdrawalsWithSignature(
            strategiesToWithdraw,
            sharesToWithdraw,
            withdrawer,
            staker,
            signature,
            expiry
        );

        /// send CCIP message to QueueWithdrawalswithSignature
        receiverContract.mockCCIPReceive(any2EvmMessage1);

        /////////////////////////////////////////////////////////////////
        ////// Complete Queued Withdrawals
        /////////////////////////////////////////////////////////////////

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: staker,
            delegatedTo: delegationManager.delegatedTo(staker),
            withdrawer: withdrawer,
            nonce: stakerNonce,
            startBlock: startBlock,
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
        });

        bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);
        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = strategiesToWithdraw[0].underlyingToken();

        Client.Any2EVMMessage memory any2EvmMessage2 = makeCCIPEigenlayerMsg_CompleteWithdrawal(
            withdrawal,
            tokensToWithdraw,
            0, // middlewareTimesIndex
            true // receiveAsTokens
        );

        vm.warp(block.timestamp + 120); // 120 seconds = 10 blocks (12second per block)
        vm.roll((block.timestamp + 120) / 12);

        // send CCIP message to CompleteWithdrawal
        receiverContract.mockCCIPReceive(any2EvmMessage2);
        /////////////////////////////////////////////////////////////////

        require(token.balanceOf(staker) == 0, "staker balance should be 0, in the ReceiverCCIP contract");
        // tokens are in the RecieverCCIP bridge contract, need to send them to the staker on L2
        console.log("balanceOfStaker after:", token.balanceOf(staker));
        require(withdrawalRoot != 0, "withdrawal root missing");

        vm.stopBroadcast();
    }


    function test_Eigenlayer_DelegateToOperator() public {

        // function delegateToBySignature(
        //     address staker,
        //     address operator,
        //     SignatureWithExpiry memory stakerSignatureAndExpiry,
        //     SignatureWithExpiry memory approverSignatureAndExpiry,
        //     bytes32 approverSalt
        // ) external {
    }

    function test_Eigenlayer_UndelegateFromOperator() public {
        // DelegationManager.undelegate

    }

    ////////////////////////////////////////////////
    // Make CCIP messages
    ////////////////////////////////////////////////

    function makeCCIPEigenlayerMsg_QueueWithdrawalsWithSignature(
            IStrategy[] memory _strategiesToWithdraw,
            uint256[] memory _sharesToWithdraw,
            address _withdrawer,
            address _staker,
            bytes memory _signature,
            uint256 _expiry
    ) public returns (
        IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory,
        Client.Any2EVMMessage memory
    ) {

        IDelegationManager.QueuedWithdrawalWithSignatureParams memory queuedWithdrawalWithSig;
        queuedWithdrawalWithSig = IDelegationManager.QueuedWithdrawalWithSignatureParams({
            strategies: _strategiesToWithdraw,
            shares: _sharesToWithdraw,
            withdrawer: _withdrawer,
            staker: _staker,
            signature: _signature,
            expiry: _expiry
        });

        IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalWithSigParams;
        queuedWithdrawalWithSigParams = new IDelegationManager.QueuedWithdrawalWithSignatureParams[](1);
        queuedWithdrawalWithSigParams[0] = queuedWithdrawalWithSig;

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(token),
            amount: 0 ether // not bridging, just sending CCIP message
        });

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0xffffffffffffffff9999999999999999eeeeeeeeeeeeeeee8888888888888888),
            sourceChainSelector: ArbSepolia.ChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(address(deployer)), // bytes: abi.decode(sender) if coming from an EVM chain.
            data: abi.encode(string(
                eigenlayerMsgEncoders.encodeQueueWithdrawalsWithSignatureMsg(
                    queuedWithdrawalWithSigParams
                )
            )), // CCIP abi.encodes a string message when sending
            destTokenAmounts: destTokenAmounts // Tokens and their amounts in their destination chain representation.
        });

        return (
            queuedWithdrawalWithSigParams,
            any2EvmMessage
        );
    }


    function makeCCIPEigenlayerMsg_CompleteWithdrawal(
        IDelegationManager.Withdrawal memory withdrawal,
        IERC20[] memory tokensToWithdraw,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    ) public returns (Client.Any2EVMMessage memory) {

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(0x0),
            amount: 0 ether // just send CCIP message, no token bridging
        });

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0xffffffffffffffff9999999999999999eeeeeeeeeeeeeeee8888888888888888),
            sourceChainSelector: ArbSepolia.ChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(deployer),
            data: abi.encode(string(
                eigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
                    withdrawal,
                    tokensToWithdraw,
                    middlewareTimesIndex,
                    receiveAsTokens
                )
            )), // CCIP abi.encodes a string message when sending
            destTokenAmounts: destTokenAmounts
        });

        return any2EvmMessage;
    }

    function makeCCIPEigenlayerMsg_DepositWithSignature(
        uint256 _amount,
        address _staker,
        uint256 expiry
    ) public returns (Client.Any2EVMMessage memory) {

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
            sourceChainSelector: ArbSepolia.ChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
            data: abi.encode(string(
                eigenlayerMsgEncoders.encodeDepositIntoStrategyWithSignatureMsg(
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
