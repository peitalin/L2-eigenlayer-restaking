// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IReceiverCCIPMock} from "./mocks/ReceiverCCIPMock.sol";
import {ISenderCCIPMock} from "./mocks/SenderCCIPMock.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";

import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {ClientSigners} from "../script/ClientSigners.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";
// 6551 accounts
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";



contract SenderHooksTests is Test {

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

    uint256 ethForkId;
    uint256 l2ForkId;

    uint256 amount = 0.003 ether;
    address mockEigenAgent = vm.addr(3333);
    uint256 expiry = block.timestamp + 1 hours;
    uint32 startBlock = uint32(block.number);
    uint256 execNonce = 0;
    uint256 withdrawalNonce = 0;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        // l2ForkId = vm.createFork("basesepolia");
        // ethForkId = vm.createSelectFork("ethsepolia");

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

        //// Configure CCIP contracts and ERC6551 EigenAgents
        (
            receiverContract,
            restakingConnector,
            agentFactory
        ) = deployReceiverOnL1Script.mockrun();

        //// Switch L2 fork
        // vm.selectFork(l2ForkId);

        clientSigners = new ClientSigners();
        deploySenderOnL2Script = new DeploySenderOnL2Script();

        (
            senderContract,
            senderHooks
        ) = deploySenderOnL2Script.mockrun();

    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_SetAndGetGasLimits() public {

        uint256[] memory gasLimits = new uint256[](2);
        gasLimits[0] = 1_000_000;
        gasLimits[1] = 800_000;

        bytes4[] memory functionSelectors = new bytes4[](2);
        functionSelectors[0] = 0xeee000aa;
        functionSelectors[1] = 0xccc555ee;

        bytes4[] memory functionSelectors2 = new bytes4[](3);
        functionSelectors2[0] = 0xeee000aa;
        functionSelectors2[1] = 0xccc555ee;
        functionSelectors2[2] = 0xaaa222ff;

        vm.startBroadcast(deployerKey);

        vm.expectRevert("input arrays must have the same length");
        senderHooks.setGasLimitsForFunctionSelectors(
            functionSelectors2,
            gasLimits
        );

        vm.expectEmit(true, true, false, false);
        emit SenderHooks.SetGasLimitForFunctionSelector(functionSelectors[0], gasLimits[0]);
        vm.expectEmit(true, true, false, false);
        emit SenderHooks.SetGasLimitForFunctionSelector(functionSelectors[1], gasLimits[1]);
        senderHooks.setGasLimitsForFunctionSelectors(
            functionSelectors,
            gasLimits
        );

        // Return default gasLimit of 400_000 for undefined function selectors
        vm.assertEq(senderHooks.getGasLimitForFunctionSelector(0xffeeaabb), 400_000);

        // gas limits should be set
        vm.assertEq(senderHooks.getGasLimitForFunctionSelector(functionSelectors[0]), 1_000_000);
        vm.assertEq(senderHooks.getGasLimitForFunctionSelector(functionSelectors[1]), 800_000);

        vm.stopBroadcast();
    }


    function test_BeforeSend_Commits_WithdrawalAgentOwnerRoot() public {

        // vm.selectFork(l2ForkId);
        vm.startBroadcast(address(senderContract));

        (
            bytes32 withdrawalRoot,
            bytes memory messageWithSignature_CW
        ) = mockCompleteWithdrawalMessage(bobKey);

        bytes32 withdrawalAgentOwnerRoot = EigenlayerMsgEncoders.calculateWithdrawalAgentOwnerRoot(
            withdrawalRoot,
            bob
        );

        vm.expectEmit(true, true, true, false);
        emit SenderHooks.WithdrawalAgentOwnerRootCommitted(
            withdrawalAgentOwnerRoot,
            mockEigenAgent, // withdrawer
            amount,
            bob // signer
        );
        // called by senderContract
        senderHooks.beforeSendCCIPMessage(
            abi.encode(string(messageWithSignature_CW)), // CCIP string encodes when messaging
            BaseSepolia.BridgeToken
        );

        vm.stopBroadcast();
    }


    function test_BeforeSendCCIPMessage_OnlySenderCCIP(uint256 signerKey) public {

        vm.assume(signerKey < type(uint256).max / 2); // EIP-2: secp256k1 curve order / 2
        vm.assume(signerKey > 1);
        address alice = vm.addr(signerKey);

        // vm.selectFork(l2ForkId);
        vm.startBroadcast(alice);

        (
            bytes32 withdrawalRoot,
            bytes memory messageWithSignature_CW
        ) = mockCompleteWithdrawalMessage(bobKey);

        bytes32 withdrawalAgentOwnerRoot = EigenlayerMsgEncoders.calculateWithdrawalAgentOwnerRoot(
            withdrawalRoot,
            alice
        );

        // Should revert if called by anyone other than senderContract
        vm.expectRevert("not called by SenderCCIP");
        senderHooks.beforeSendCCIPMessage(
            abi.encode(string(messageWithSignature_CW)), // CCIP string encodes when messaging
            BaseSepolia.BridgeToken
        );

        vm.stopBroadcast();
    }

    function test_BeforeSendCCIPMessage_TokenCannotBeNull() public {

        // vm.selectFork(l2ForkId);
        vm.startBroadcast(address(senderContract));

        (
            bytes32 withdrawalRoot,
            bytes memory messageWithSignature_CW
        ) = mockCompleteWithdrawalMessage(bobKey);

        vm.expectRevert("SenderHooks._commitWithdrawalAgentOwnerRootInfo: cannot commit tokenL2 as address(0)");
        senderHooks.beforeSendCCIPMessage(
            abi.encode(string(messageWithSignature_CW)), // CCIP string encodes when messaging
            address(0) // tokenL2
        );

        vm.stopBroadcast();
    }


    function mockCompleteWithdrawalMessage(uint256 signerKey) public view
        returns (
            bytes32 withdrawalRoot,
            bytes memory messageWithSignature_CW
        )
    {

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);
        strategiesToWithdraw[0] = strategy;
        sharesToWithdraw[0] = amount;

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: mockEigenAgent,
            delegatedTo: vm.addr(5656),
            withdrawer: mockEigenAgent,
            nonce: withdrawalNonce,
            startBlock: startBlock,
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
        });

        withdrawalRoot = senderHooks.calculateWithdrawalRoot(withdrawal);

        bytes memory completeWithdrawalMessage;
        {
            // create the completeWithdrawal message for Eigenlayer
            IERC20[] memory tokensToWithdraw = new IERC20[](1);
            tokensToWithdraw[0] = tokenL1;

            completeWithdrawalMessage = EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                0, //middlewareTimesIndex,
                true // receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = clientSigners.signMessageForEigenAgentExecution(
                signerKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager),
                completeWithdrawalMessage,
                execNonce,
                expiry
            );
        }

        return (
            withdrawalRoot,
            messageWithSignature_CW
        );
    }

}
