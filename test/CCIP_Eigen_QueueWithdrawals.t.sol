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

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EthSepolia, ArbSepolia} from "../script/Addresses.sol";


contract CCIP_Eigen_QueueWithdrawals is Test {

    DeployOnEthScript public deployOnEthScript;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    SignatureUtilsEIP1271 public signatureUtils;
    EigenlayerMsgEncoders public eigenlayerMsgEncoders;

    uint256 public deployerKey;
    address public deployer;

    IReceiverCCIP public receiverContract;
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

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deployOnEthScript = new DeployOnEthScript();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        eigenlayerMsgEncoders = new EigenlayerMsgEncoders();
        signatureUtils = new SignatureUtilsEIP1271();

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

        erc20Minter = IERC20Minter(address(token));

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
        vm.startBroadcast(EthSepolia.Router); // simulate router sending message to receiverContract on L1
        Client.Any2EVMMessage memory any2EvmMessage = makeCCIPEigenlayerDepositMessage(
            amountToStake,
            deployer,
            block.timestamp + 1 hours
        );
        receiverContract.mockCCIPReceive(any2EvmMessage);

        uint256 valueOfShares = strategy.userUnderlying(address(deployer));
        address staker = deployer;

        stakerShares = strategyManager.stakerStrategyShares(staker, strategy);

        require(valueOfShares == amountToStake, "valueofShares incorrect");
        require(stakerShares == amountToStake, "stakerStrategyShares incorrect");

        vm.stopBroadcast();
    }



    function test_Eigenlayer_QueueWithdrawal() public {

        vm.startBroadcast(deployer);

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
            withdrawer: deployer
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
            sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
            data: abi.encode(string(
                eigenlayerMsgEncoders.encodeQueueWithdrawalMsg(
                    queuedWithdrawalParams
                )
            )), // CCIP abi.encodes a string message when sending
            destTokenAmounts: destTokenAmounts // Tokens and their amounts in their destination chain representation.
        });

        bytes32[] memory withdrawalRoots = delegationManager.queueWithdrawals(queuedWithdrawalParams);

        /////////////////////////////////////////////////////////////////
        ////// Complete Queued Withdrawals
        /////////////////////////////////////////////////////////////////

        console.log("withdrawalRoot");
        console.logBytes32(withdrawalRoots[0]);

        // IDelegationManager.Withdrawal[] memory withdrawals = new IDelegationManager.Withdrawal[](1);
        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: deployer, // msg.sender
            delegatedTo: address(0), // not delegated to anyone
            withdrawer: deployer,
            nonce: 0,
            startBlock: uint32(block.number),
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
        });

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = strategy.underlyingToken();
        uint256 middlewareTimesIndex = 0; // not used, used when slashing is enabled
        bool receiveAsTokens = true;

        uint256 newTimestamp = block.timestamp + 60; // 60 seconds = 5 blocks (12second per block)
        vm.warp(newTimestamp);
        vm.roll(newTimestamp / 12);

        uint256 delay = delegationManager.getWithdrawalDelay(strategiesToWithdraw);

        // console.log("block.timestamp :", block.timestamp);
        // console.log("block.number :", block.number);
        // console.log("withdrawal delay (blocks)", delay); // 4 blocks withdrawal delay

        delegationManager.completeQueuedWithdrawal(
            withdrawal,
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );

        uint256 balanceOfDeployer = token.balanceOf(deployer);
        // console.log("balanceOfDeployer:", balanceOfDeployer);


        vm.stopBroadcast();
        // /**
        //  * Struct type used to specify an existing queued withdrawal. Rather than storing the entire struct, only a hash is stored.
        //  * In functions that operate on existing queued withdrawals -- e.g. completeQueuedWithdrawal`, the data is resubmitted and the hash of the submitted
        //  * data is computed by `calculateWithdrawalRoot` and checked against the stored hash in order to confirm the integrity of the submitted data.
        //  */
        // struct Withdrawal {
        //     // The address that originated the Withdrawal
        //     address staker;
        //     // The address that the staker was delegated to at the time that the Withdrawal was created
        //     address delegatedTo;
        //     // The address that can complete the Withdrawal + will receive funds when completing the withdrawal
        //     address withdrawer;
        //     // Nonce used to guarantee that otherwise identical withdrawals have unique hashes
        //     uint256 nonce;
        //     // Block number when the Withdrawal was created
        //     uint32 startBlock;
        //     // Array of strategies that the Withdrawal contains
        //     IStrategy[] strategies;
        //     // Array containing the amount of shares in each Strategy in the `strategies` array
        //     uint256[] shares;
        // }

        // function completeQueuedWithdrawal(
        //     Withdrawal calldata withdrawal,
        //     IERC20[] calldata tokens,
        //     uint256 middlewareTimesIndex,
        //     bool receiveAsTokens
        // ) external onlyWhenNotPaused(PAUSED_EXIT_WITHDRAWAL_QUEUE) nonReentrant {
        //     _completeQueuedWithdrawal(withdrawal, tokens, middlewareTimesIndex, receiveAsTokens);
        // }

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


        // DelegationManager.queueWithdrawals
        // DelegationManager.completeQueuedWithdrawal
        // DelegationManager.completeQueuedWithdrawals
    }

    function makeCCIPEigenlayerDepositMessage(
        uint256 amount,
        address staker,
        uint256 expiry
    ) public returns (Client.Any2EVMMessage memory) {

        uint256 nonce = 0; // in production retrieve on StrategyManager on L1
        bytes32 domainSeparator = signatureUtils.getDomainSeparator(address(strategyManager), block.chainid);

        (bytes memory signature, bytes32 digestHash) = signatureUtils.createEigenlayerSignature(
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
            token: address(token),
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
