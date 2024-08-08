// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IMockERC20} from "../src/IMockERC20.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/IReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector, EigenlayerDepositWithSignatureParams} from "../src/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EthSepolia, ArbSepolia} from "../script/Addresses.sol";


contract CCIP_Eigen_QueueWithdrawal is Test {

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

    uint256 public initialReceiverBalance = 5 ether;

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

        mockERC20 = IMockERC20(address(token));

        //////////////////////////////////////
        // Broadcast
        //////////////////////////////////////
        vm.startBroadcast(deployerKey);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);
        // fund receiver with tokens from CCIP bridge: EVM2EVMOffRamp contract
        mockERC20.mint(address(receiverContract), initialReceiverBalance);
        receiverContract.allowlistSender(deployer, true);
        vm.stopBroadcast();

        /////////////////////////////////////
        //// Send message from CCIP to Eigenlayer
        /////////////////////////////////////
        vm.startBroadcast(EthSepolia.Router); // simulate router sending message to receiverContract on L1
        Client.Any2EVMMessage memory any2EvmMessage = createEigenlayerDepositMessage();
        receiverContract.mockCCIPReceive(any2EvmMessage);
        vm.stopBroadcast();


    }


    function createEigenlayerDepositMessage() public returns (Client.Any2EVMMessage memory) {

        uint256 amount = 0.0099 ether;
        address staker = deployer;
        uint256 expiry = block.timestamp + 1 hours;
        uint256 nonce = 0;
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
            messageId: bytes32(0xffffffffffff8888888888888888881111111111111111111111111222222222),
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

    function test_Eigenlayer_QueueWithdrawal() public {

    }

    function test_Eigenlayer_QueueWithdrawals() public {

        // function queueWithdrawals(
        //     QueuedWithdrawalParams[] calldata queuedWithdrawalParams
        // ) external onlyWhenNotPaused(PAUSED_ENTER_WITHDRAWAL_QUEUE) returns (bytes32[] memory) {

        // struct QueuedWithdrawalParams {
        //     // Array of strategies that the QueuedWithdrawal contains
        //     IStrategy[] strategies;
        //     // Array containing the amount of shares in each Strategy in the `strategies` array
        //     uint256[] shares;
        //     // The address of the withdrawer
        //     address withdrawer;
        // }

        // DelegationManager.queueWithdrawals
        // DelegationManager.completeQueuedWithdrawal
        // DelegationManager.completeQueuedWithdrawals
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
