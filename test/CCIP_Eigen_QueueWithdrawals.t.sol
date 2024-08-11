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

        // staker = address(receiverContract);
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
        Client.Any2EVMMessage memory any2EvmMessage = makeCCIPEigenlayerDepositMessage(
            amountToStake,
            staker,
            block.timestamp + 1 hours
        );
        receiverContract.mockCCIPReceive(any2EvmMessage);

        uint256 valueOfShares = strategy.userUnderlying(staker);

        stakerShares = strategyManager.stakerStrategyShares(staker, strategy);
        uint256 receiverShares = strategyManager.stakerStrategyShares(address(receiverContract), strategy);

        require(valueOfShares == amountToStake, "valueofShares incorrect");
        require(stakerShares == amountToStake, "stakerStrategyShares incorrect");
        console.log("stakerShares:", stakerShares);
        console.log("receiverShares:", receiverShares);

        vm.stopBroadcast();
    }



    function test_Eigenlayer_QueueWithdrawal() public {

        vm.startBroadcast(staker);

        /////////////////////////////////////////////////////////////////
        ////// Queue Withdrawal
        /////////////////////////////////////////////////////////////////

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = stakerShares;

        IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal;
        queuedWithdrawal = IDelegationManager.QueuedWithdrawalParams({
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw,
            // withdrawer: address(receiverContract)
            withdrawer: staker
            // @note must be receiverContract
        });

        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams;
        queuedWithdrawalParams = new IDelegationManager.QueuedWithdrawalParams[](1);
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

        // receiverContract.mockCCIPReceive(any2EvmMessage);

        uint256 stakerNonce = 0; // implement getNonce on DelegationManager
        bytes32 digestHash = signatureUtils.calculateQueueWithdrawalDigestHash(
            staker,
            queuedWithdrawal.strategies,
            queuedWithdrawal.shares,
            stakerNonce,
            address(delegationManager),
            block.chainid
        );

        // generate ECDSA signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        signatureUtils.checkSignature_EIP1271(staker, digestHash, signature);

        delegationManager.queueWithdrawalsWithSignature(
            queuedWithdrawalParams,
            staker,
            signature
        );

        console.log("balanceOfStaker before:", token.balanceOf(staker));

        /////////////////////////////////////////////////////////////////
        ////// Complete Queued Withdrawals
        /////////////////////////////////////////////////////////////////

        // IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal[](1);
        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            // staker: address(receiverContract), // msg.sender
            staker: staker,
            delegatedTo: address(0), // not delegated to anyone
            withdrawer: staker,
            nonce: 0,
            startBlock: uint32(block.number),
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
        });

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = strategy.underlyingToken();

        vm.warp(block.timestamp + 120); // 120 seconds = 10 blocks (12second per block)
        vm.roll((block.timestamp + 120) / 12);
        // delegationManager.getWithdrawalDelay(strategiesToWithdraw);

        delegationManager.completeQueuedWithdrawal(
            withdrawal,
            tokensToWithdraw,
            0, // middlewareTimesIndex
            true // receiveAsTokens
        );

        console.log("balanceOfStaker after:", token.balanceOf(staker));
        console.log("amountToStake:", amountToStake);

        vm.stopBroadcast();
    }


    function makeCCIPEigenlayerDepositMessage(
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


    function test_Eigenlayer_CompleteQueuedWithdrawals() public {
        // function completeQueuedWithdrawals(
        //     Withdrawal[] calldata withdrawals,
        //     IERC20[][] calldata tokens,
        //     uint256[] calldata middlewareTimesIndexes,
        //     bool[] calldata receiveAsTokens
        // ) external onlyWhenNotPaused(PAUSED_EXIT_WITHDRAWAL_QUEUE) nonReentrant {
        //     for (uint256 i = 0; i < withdrawals.length; ++i) {
        //         _completeQueuedWithdrawal(withdrawals[i], tokens[i], middlewareTimesIndexes[i], receiveAsTokens[i]);
        //     }
        // }
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

}
