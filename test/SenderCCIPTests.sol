// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IReceiverCCIPMock} from "./mocks/ReceiverCCIPMock.sol";
import {ISenderCCIPMock} from "./mocks/SenderCCIPMock.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
import {BaseMessengerCCIP} from "../src/BaseMessengerCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";

import {ClientSigners} from "../script/ClientSigners.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";
// 6551 accounts
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";



contract SenderCCIPTests is Test {

    DeployReceiverOnL1Script public deployReceiverOnL1Script;
    DeploySenderOnL2Script public deploySenderOnL2Script;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    ClientSigners public clientSigners;

    IReceiverCCIPMock public receiverContract;
    IRestakingConnector public restakingConnector;

    IAgentFactory public agentFactory;
    EigenAgentOwner721 public eigenAgentOwnerNft;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IERC20 public tokenL1;
    IStrategy public strategy;

    ISenderCCIPMock public senderContract;
    ISenderHooks public senderHooks;

    uint256 deployerKey;
    address deployer;
    uint256 bobKey;
    address bob;

    uint256 amount = 0.003 ether;
    bytes4 randomFunctionSelector;
    bytes randomMessage;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        bobKey = uint256(56789);
        bob = vm.addr(bobKey);
        vm.deal(bob, 1 ether);

        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        //// Configure Eigenlayer contracts
        (
            strategy,
            strategyManager,
            , // IStrategyFactory
            , // pauserRegistry
            delegationManager,
            , // rewardsCoordinator
            tokenL1
        ) = deployMockEigenlayerContractsScript.deployEigenlayerContracts(false);

        (
            receiverContract,
            restakingConnector,
            agentFactory
        ) = deployReceiverOnL1Script.mockrun();

        clientSigners = new ClientSigners();
        deploySenderOnL2Script = new DeploySenderOnL2Script();

        (
            senderContract,
            senderHooks
        ) = deploySenderOnL2Script.mockrun();

        vm.startBroadcast(deployer);
        senderContract.allowlistSender(deployer, true);
        vm.stopBroadcast();

        randomFunctionSelector = bytes4(keccak256("someRandomFunction(uint256)"));
        randomMessage = abi.encodeWithSelector(randomFunctionSelector, 1);
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_SetAndGetSenderHooks() public {

        address newSenderHooks = vm.addr(9981);

        vm.startBroadcast(bob);
        {
            vm.expectRevert("Ownable: caller is not the owner");
            senderContract.setSenderHooks(ISenderHooks(newSenderHooks));
        }
        vm.stopBroadcast();

        vm.startBroadcast(deployer);
        {
            // check senderHooks != address(0)
            vm.expectRevert("_senderHooks cannot be address(0)");
            senderContract.setSenderHooks(ISenderHooks(address(0)));
            // set senderHooks
            senderContract.setSenderHooks(ISenderHooks(newSenderHooks));
            // get senderHooks
            vm.assertEq(address(senderContract.getSenderHooks()), newSenderHooks);
        }
        vm.stopBroadcast();
    }

    function test_MockReceive_RandomMessage_WithTokens() public {

        vm.startBroadcast(address(senderContract));
        {
            Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
            destTokenAmounts[0] = Client.EVMTokenAmount({
                token: BaseSepolia.BridgeToken, // CCIP-BnM token address on L2
                amount: amount
            });

            Client.Any2EVMMessage memory ccipMessage = Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(address(deployer)),
                data: abi.encode(string(
                    randomMessage
                )),
                destTokenAmounts: destTokenAmounts
            });

            vm.expectEmit(true, true, true, true);
            emit SenderCCIP.MatchedReceivedFunctionSelector(randomFunctionSelector);

            vm.expectEmit(true, true, true, true);
            emit BaseMessengerCCIP.MessageReceived(
                ccipMessage.messageId,
                ccipMessage.sourceChainSelector,
                address(deployer),
                "unknown message",
                destTokenAmounts[0].token,
                destTokenAmounts[0].amount
            );
            // event MessageReceived(
            //     bytes32 indexed messageId,
            //     uint64 indexed sourceChainSelector,
            //     address sender,
            //     string text,
            //     address token,
            //     uint256 tokenAmount
            // );
            senderContract.mockCCIPReceive(
                ccipMessage
        );

        }
        vm.stopBroadcast();
    }

    function test_MockReceive_RandomMessage_NoTokens() public {

        vm.startBroadcast(address(senderContract));
        {
            Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](0);

            Client.Any2EVMMessage memory ccipMessage = Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(address(deployer)),
                data: abi.encode(string(
                    randomMessage
                )),
                destTokenAmounts: destTokenAmounts
            });

            vm.expectEmit(true, true, true, true);
            emit SenderCCIP.MatchedReceivedFunctionSelector(randomFunctionSelector);

            vm.expectEmit(true, true, true, true);
            emit BaseMessengerCCIP.MessageReceived(
                ccipMessage.messageId,
                ccipMessage.sourceChainSelector,
                address(deployer),
                "unknown message",
                address(0),
                0
            );
            // event MessageReceived(
            //     bytes32 indexed messageId,
            //     uint64 indexed sourceChainSelector,
            //     address sender,
            //     string text,
            //     address token,
            //     uint256 tokenAmount
            // );
            senderContract.mockCCIPReceive(
                ccipMessage
            );
        }
        vm.stopBroadcast();
    }

}
