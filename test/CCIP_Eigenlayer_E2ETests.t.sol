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

import {IMockERC20} from "../src/IMockERC20.sol";
import {MsgForEigenlayer} from "../src/RestakingConnector.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/IReceiverCCIP.sol";
import {IRestakingConnector} from "../src/IRestakingConnector.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";




contract CCIPEigenlayerE2ETest is Test {

    DeployOnEthScript public deployOnEthScript;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    uint256 public deployerKey;
    address public deployer;

    IReceiverCCIP public receiverContract;
    IRestakingConnector public restakingConnector;

    event EigenlayerContractCallParams(
        bytes4 indexed functionSelector,
        uint256 indexed amount,
        address indexed staker
    );

    uint256 amountBridgedAndStaked;


    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        deployOnEthScript = new DeployOnEthScript();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        amountBridgedAndStaked = 0.0093 ether;
    }

    function test_ReceiverDepositsInEigenlayer() public {

        /////////////////////////////////////
        //// Configure CCIP contracts
        /////////////////////////////////////
        address router = address(0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59);
        (
            receiverContract,
            restakingConnector
        ) = deployOnEthScript.run();

        /////////////////////////////////////
        //// Configure Eigenlayer contracts
        /////////////////////////////////////
        (
            IStrategyManager strategyManager,
            IPauserRegistry _pauserRegistry,
            IRewardsCoordinator _rewardsCoordinator,
            IDelegationManager delegationManager,
            IStrategy strategy
        ) = deployMockEigenlayerContractsScript.run();

        /////////////////////////////////////
        //// Connect CCIP Receiver to Eigenlayer contracts and whitelist strategy
        /////////////////////////////////////
        vm.startBroadcast(deployerKey);

        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

        IMockERC20 token = IMockERC20(address(strategy.underlyingToken()));
        console.log("underlying strategy token:", address(token));

        // mock receiver recieving tokens from CCIP bridge: EVM2EVMOffRamp contrat
        token.mint(address(receiverContract), 2e18);
        vm.stopBroadcast();

        /////////////////////////////////////
        //// Send message from CCIP to Eigenlayer
        /////////////////////////////////////
        vm.startBroadcast(deployerKey);
        bytes memory sender_bytes = hex"0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c";
        receiverContract.allowlistSender(abi.decode(sender_bytes, (address)), true);
        vm.stopBroadcast();


        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(token), // CCIP-BnM token address on Eth Sepolia.
            amount: amountBridgedAndStaked
        });

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0x598fff8ee56c84a5d8793c1ac075501711392720209f72ae3cfb445d4116d272),
            sourceChainSelector: 3478487238524512106, // Arb Sepolia source chain selector
            sender: sender_bytes, // bytes: abi.decode(sender) if coming from an EVM chain.
            data: abi.encode(string(abi.encodeWithSelector(
                bytes4(keccak256("depositIntoStrategy(uint256,address)")),
                amountBridgedAndStaked,
                deployer
            ))), // CCIP abi.encodes the string message when sending
            destTokenAmounts: destTokenAmounts // Tokens and their amounts in their destination chain representation.
        });


        // simulate router sending message to receiverContract on L1
        vm.startBroadcast(router);
        // (first 3 args: check indexed topics), (4th arg = true = check data)
        vm.expectEmit(true, true, true, true);
        // the event we expect
        emit EigenlayerContractCallParams(hex"f7e784ef", amountBridgedAndStaked, address(0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c));
        receiverContract.mockCCIPReceive(any2EvmMessage);

        uint256 receiverBalance = token.balanceOf(address(receiverContract));
        console.log("receiver balance:", receiverBalance);

        uint256 valueOfShares = strategy.userUnderlying(address(receiverContract));
        console.log("receiver shares value:", valueOfShares);

        vm.stopBroadcast();
    }

}
