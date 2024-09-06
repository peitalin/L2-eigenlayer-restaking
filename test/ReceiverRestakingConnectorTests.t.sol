// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {AgentFactory} from "../src/6551/AgentFactory.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";



contract ReceiverRestakingConnectorTests is BaseTestEnvironment {

    error AddressZero(string msg);

    uint256 expiry;
    uint256 execNonce0;

    function setUp() public {

        setUpLocalEnvironment();

        expiry = block.timestamp + 1 hours;
        execNonce0 = 0;
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

     function test_SetContracts_Receiver() public {

        IRestakingConnector restakingImpl = IRestakingConnector(address(new RestakingConnector()));

        vm.expectRevert("Ownable: caller is not the owner");
        receiverContract.setRestakingConnector(IRestakingConnector(address(0)));

        vm.expectRevert("Ownable: caller is not the owner");
        receiverContract.setSenderContractL2Addr(address(senderContract));

        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(AddressZero.selector,
            "SenderContract on L2 cannot be address(0)"));
        receiverContract.setSenderContractL2Addr(address(0));

        vm.expectRevert(abi.encodeWithSelector(AddressZero.selector,
            "RestakingConnector cannot be address(0)"));
        vm.prank(deployer);
        receiverContract.setRestakingConnector(IRestakingConnector(address(0)));

        vm.prank(deployer);
        receiverContract.setRestakingConnector(restakingImpl);

        vm.assertEq(
            address(receiverContract.getRestakingConnector()),
            address(restakingImpl)
        );
     }

     function test_Initialize_Receiver() public {

        ReceiverCCIP receiverImpl = new ReceiverCCIP(EthSepolia.Router, EthSepolia.Link);
        ProxyAdmin pa = new ProxyAdmin();

        vm.expectRevert(
            abi.encodeWithSelector(AddressZero.selector, "RestakingConnector cannot be address(0)")
        );
        new TransparentUpgradeableProxy(
            address(receiverImpl),
            address(pa),
            abi.encodeWithSelector(
                ReceiverCCIP.initialize.selector,
                address(0),
                address(senderContract)
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(AddressZero.selector, "SenderCCIP cannot be address(0)")
        );
        new TransparentUpgradeableProxy(
            address(receiverImpl),
            address(pa),
            abi.encodeWithSelector(
                ReceiverCCIP.initialize.selector,
                address(restakingConnector),
                address(0)
            )
        );
    }

     function test_Initialize_RestakingConnector() public {

        RestakingConnector restakingImpl = new RestakingConnector();
        ProxyAdmin pa = new ProxyAdmin();

        vm.expectRevert(
            abi.encodeWithSelector(AddressZero.selector, "AgentFactory cannot be address(0)")
        );
        new TransparentUpgradeableProxy(
            address(restakingImpl),
            address(pa),
            abi.encodeWithSelector(
                RestakingConnector.initialize.selector,
                address(0)
            )
        );
    }

    function test_OnlyReceiverCanCall_RestakingConnector() public {

        bytes memory messageWithSignature_M;
        {
            bytes memory mintEigenAgentMessage = encodeMintEigenAgent();

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_M = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager),
                mintEigenAgentMessage,
                execNonce0,
                expiry
            );
        }

        bytes memory ccipMessage = abi.encode(string(messageWithSignature_M));

        vm.expectRevert("not called by ReceiverCCIP");
        restakingConnector.mintEigenAgent(
            ccipMessage
        );

        vm.expectRevert("not called by ReceiverCCIP");
        restakingConnector.depositWithEigenAgent(
            ccipMessage
        );

        vm.expectRevert("not called by ReceiverCCIP");
        restakingConnector.queueWithdrawalsWithEigenAgent(
            ccipMessage
        );

        vm.expectRevert("not called by ReceiverCCIP");
        restakingConnector.completeWithdrawalWithEigenAgent(
            ccipMessage
        );

        vm.expectRevert("not called by ReceiverCCIP");
        restakingConnector.delegateToWithEigenAgent(
            ccipMessage
        );

        vm.expectRevert("not called by ReceiverCCIP");
        restakingConnector.undelegateWithEigenAgent(
            ccipMessage
        );
    }

    function test_MintEigenAgent() public {

        bytes memory messageWithSignature_M;
        {
            bytes memory mintEigenAgentMessage = encodeMintEigenAgent();

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_M = signMessageForEigenAgentExecution(
                deployerKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager),
                mintEigenAgentMessage,
                execNonce0,
                expiry
            );
        }

        vm.prank(deployer);
        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector, // Arb Sepolia source chain selector
                sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
                data: abi.encode(string(
                    messageWithSignature_M
                )), // CCIP abi.encodes a string message when sending
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );

        IEigenAgent6551 eAgent = agentFactory.getEigenAgent(deployer);
        require(address(eAgent) != address(0), "should have minted a new EigenAgent");
    }

    function test_SetAndGet_QueueWithdrawalBlock() public {

        vm.expectRevert("Not admin or owner");
        restakingConnector.setQueueWithdrawalBlock(deployer, 22, 9999);

        vm.prank(deployer);
        restakingConnector.setQueueWithdrawalBlock(deployer, 22, 9999);

        uint256 withdrawalBlock = restakingConnector.getQueueWithdrawalBlock(deployer, 22);
        vm.assertEq(withdrawalBlock, 9999);
    }


    function test_SetAndGet_AgentFactory() public {

        vm.expectRevert("Ownable: caller is not the owner");
        restakingConnector.setAgentFactory(
            address(agentFactory)
        );

        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(AddressZero.selector, "AgentFactory cannot be address(0)")
        );
        restakingConnector.setAgentFactory(
            address(0)
        );

        vm.prank(deployer);
        restakingConnector.setAgentFactory(
            address(agentFactory)
        );

        address af = restakingConnector.getAgentFactory();
        vm.assertEq(af, address(agentFactory));
    }

    function test_SetAndGet_EigenlayerContracts() public {

        vm.expectRevert("Ownable: caller is not the owner");
        restakingConnector.setEigenlayerContracts(
            delegationManager,
            strategyManager,
            strategy
        );

        vm.startBroadcast(deployer);
        {
            vm.expectRevert(
                abi.encodeWithSelector(AddressZero.selector, "_delegationManager cannot be address(0)")
            );
            restakingConnector.setEigenlayerContracts(
                IDelegationManager(address(0)),
                strategyManager,
                strategy
            );

            vm.expectRevert(
                abi.encodeWithSelector(AddressZero.selector, "_strategyManager cannot be address(0)")
            );
            restakingConnector.setEigenlayerContracts(
                delegationManager,
                IStrategyManager(address(0)),
                strategy
            );

            vm.expectRevert(
                abi.encodeWithSelector(AddressZero.selector, "_strategy cannot be address(0)")
            );
            restakingConnector.setEigenlayerContracts(
                delegationManager,
                strategyManager,
                IStrategy(address(0))
            );

            restakingConnector.setEigenlayerContracts(
                delegationManager,
                strategyManager,
                strategy
            );

            (
                IDelegationManager _delegationManager,
                IStrategyManager _strategyManager,
                IStrategy _strategy
            ) = restakingConnector.getEigenlayerContracts();

            vm.assertEq(address(delegationManager), address(_delegationManager));
            vm.assertEq(address(strategyManager), address(_strategyManager));
            vm.assertEq(address(strategy), address(_strategy));
        }
        vm.stopBroadcast();
    }

    function test_SetAndGet_GasLimits_RestakingConnector() public {

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
        restakingConnector.setGasLimitsForFunctionSelectors(
            functionSelectors2,
            gasLimits
        );

        vm.expectEmit(true, true, false, false);
        emit SenderHooks.SetGasLimitForFunctionSelector(functionSelectors[0], gasLimits[0]);
        vm.expectEmit(true, true, false, false);
        emit SenderHooks.SetGasLimitForFunctionSelector(functionSelectors[1], gasLimits[1]);
        restakingConnector.setGasLimitsForFunctionSelectors(
            functionSelectors,
            gasLimits
        );

        // Return default gasLimit of 400_000 for undefined function selectors
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelector(0xffeeaabb), 400_000);

        // gas limits should be set
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelector(functionSelectors[0]), 1_000_000);
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelector(functionSelectors[1]), 800_000);

        vm.stopBroadcast();
    }

}
