// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {AgentFactory} from "../src/6551/AgentFactory.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";



contract UnitTests_ReceiverRestakingConnector is BaseTestEnvironment {

    error AddressZero(string msg);
    error CallerNotWhitelisted(string reason);
    error SignatureInvalid(string reason);

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

    function test_HandleCustomError_InvalidTargetContract() public {

        uint256 execNonce = 0;
        uint256 expiryShort = block.timestamp + 60 seconds;
        uint256 amount = 0.1 ether;

        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            bobKey,
            block.chainid,
            address(123123), // invalid targetContract to cause revert
            encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            ),
            execNonce,
            expiryShort
        );

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1), // CCIP-BnM token address on Eth Sepolia.
            amount: amount
        });
        bytes32 messageId1 = bytes32(abi.encode(0x123333444555));
        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: messageId1,
            sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
            sender: abi.encode(deployer),
            destTokenAmounts: destTokenAmounts,
            data: abi.encode(string(
                messageWithSignature
            ))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IRestakingConnector.ExecutionErrorRefundAfterExpiry.selector,
                "Invalid signer, or incorrect digestHash parameters.",
                "Manually execute to refund after timestamp:",
                expiryShort
            )
        );
        receiverContract.mockCCIPReceive(any2EvmMessage);

        vm.prank(deployer);
        receiverContract.setAmountRefundedToMessageId(messageId1, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRestakingConnector.EigenAgentExecutionErrorStr.selector,
                bob,
                expiryShort,
                "Invalid signer, or incorrect digestHash parameters."
            )
        );
        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    function test_HandleCustomError_CallerNotAllowed() public {

        uint256 execNonce = 0;
        uint256 expiryShort = block.timestamp + 60 seconds;
        uint256 amount = 0.1 ether;

        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            bobKey,
            block.chainid,
            address(strategyManager),
            encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            ),
            execNonce,
            expiryShort
        );

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1), // CCIP-BnM token address on Eth Sepolia.
            amount: amount
        });
        bytes32 messageId1 = bytes32(abi.encode(0x123333444555));
        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: messageId1,
            sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
            sender: abi.encode(deployer),
            destTokenAmounts: destTokenAmounts,
            data: abi.encode(string(
                messageWithSignature
            ))
        });

        // introduce error: remove whitelisted caller
        vm.prank(deployer);
        eigenAgentOwner721.removeFromWhitelistedCallers(address(restakingConnector));

        vm.expectRevert(abi.encodeWithSelector(CallerNotWhitelisted.selector, "EigenAgent: caller not allowed"));
        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    function test_ReceiverL1_HandleCustomDepositError_BubbleErrorsUp() public {

        uint256 execNonce = 0;
        // should revert with EigenAgentExecutionError(signer, expiry)
        address invalidEigenlayerStrategy = vm.addr(4444);
        // make expiryShort to test refund on expiry feature
        uint256 expiryShort = block.timestamp + 60 seconds;
        uint256 amount = 0.1 ether;

        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            bobKey,
            block.chainid, // destination chainid where EigenAgent lives
            address(strategyManager), // StrategyManager to approve + deposit
            encodeDepositIntoStrategyMsg(
                invalidEigenlayerStrategy,
                address(tokenL1),
                amount
            ),
            execNonce,
            expiryShort
        );

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1), // CCIP-BnM token address on Eth Sepolia.
            amount: amount
        });
        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0x0),
            sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
            sender: abi.encode(deployer),
            destTokenAmounts: destTokenAmounts,
            data: abi.encode(string(
                messageWithSignature
            ))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IRestakingConnector.ExecutionErrorRefundAfterExpiry.selector,
                "StrategyManager.onlyStrategiesWhitelistedForDeposit: strategy not whitelisted",
                "Manually execute to refund after timestamp:",
                expiryShort
            )
        );
        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    function test_OnlyReceiverCanCall_RestakingConnector() public {

        bytes memory mintEigenAgentMessage = encodeMintEigenAgentMsg(bob);

        bytes memory ccipMessage = abi.encode(string(mintEigenAgentMessage));

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

    function test_ReceiverL1_MintEigenAgent() public {

        bytes memory mintEigenAgentMessageBob = encodeMintEigenAgentMsg(bob);

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
                sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
                data: abi.encode(string(
                    mintEigenAgentMessageBob
                )), // CCIP abi.encodes a string message when sending
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );

        require(
            address(agentFactory.getEigenAgent(bob)) != address(0),
            "Bob should have minted a new EigenAgent"
        );

        bytes memory mintEigenAgentMessageAlice = encodeMintEigenAgentMsg(alice);

        vm.prank(bob);
        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
                sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
                data: abi.encode(string(
                    mintEigenAgentMessageAlice
                )), // CCIP abi.encodes a string message when sending
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );
        require(
            address(agentFactory.getEigenAgent(alice)) != address(0),
            "Bob should have minted a new EigenAgent for Alice"
        );
        require(
            address(agentFactory.getEigenAgent(deployer)) == address(0),
            "Deployer should not have minted a new EigenAgent"
        );
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
            strategy,
            rewardsCoordinator
        );

        vm.startBroadcast(deployer);
        {
            vm.expectRevert(
                abi.encodeWithSelector(AddressZero.selector, "_delegationManager cannot be address(0)")
            );
            restakingConnector.setEigenlayerContracts(
                IDelegationManager(address(0)),
                strategyManager,
                strategy,
                rewardsCoordinator
            );

            vm.expectRevert(
                abi.encodeWithSelector(AddressZero.selector, "_strategyManager cannot be address(0)")
            );
            restakingConnector.setEigenlayerContracts(
                delegationManager,
                IStrategyManager(address(0)),
                strategy,
                rewardsCoordinator
            );

            vm.expectRevert(
                abi.encodeWithSelector(AddressZero.selector, "_strategy cannot be address(0)")
            );
            restakingConnector.setEigenlayerContracts(
                delegationManager,
                strategyManager,
                IStrategy(address(0)),
                rewardsCoordinator
            );

            vm.expectRevert(
                abi.encodeWithSelector(AddressZero.selector, "_rewardsCoordinator cannot be address(0)")
            );
            restakingConnector.setEigenlayerContracts(
                delegationManager,
                strategyManager,
                strategy,
                IRewardsCoordinator(address(0))
            );


            restakingConnector.setEigenlayerContracts(
                delegationManager,
                strategyManager,
                strategy,
                rewardsCoordinator
            );

            (
                IDelegationManager _delegationManager,
                IStrategyManager _strategyManager,
                IStrategy _strategy,
                IRewardsCoordinator _rewardsCoordinator
            ) = restakingConnector.getEigenlayerContracts();

            vm.assertEq(address(delegationManager), address(_delegationManager));
            vm.assertEq(address(strategyManager), address(_strategyManager));
            vm.assertEq(address(strategy), address(_strategy));
            vm.assertEq(address(rewardsCoordinator), address(_rewardsCoordinator));
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
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelector(0xffeeaabb), 200_000);

        // gas limits should be set
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelector(functionSelectors[0]), 1_000_000);
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelector(functionSelectors[1]), 800_000);

        vm.stopBroadcast();
    }

    function test_ReceiverL1_dispatchMessageToEigenAgent_InternalCallsOnly(address user) public {

        vm.assume(user != address(receiverContract));
        vm.assume(user != deployer);

        vm.prank(user);

        vm.expectRevert("Function not called internally");
        receiverContract.dispatchMessageToEigenAgent(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                data: abi.encode(string(
                    encodeMintEigenAgentMsg(deployer)
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            }),
            address(tokenL1),
            1 ether
        );
    }

    function test_SetandGet_AmountRefunded() public {

        bytes32 messageId = bytes32(abi.encode(1,2,3));

        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        receiverContract.setAmountRefundedToMessageId(messageId , 1 ether);

        vm.prank(deployer);
        receiverContract.setAmountRefundedToMessageId(messageId , 1.3 ether);

        vm.assertEq(
            receiverContract.amountRefunded(messageId ),
            1.3 ether
        );
    }
}
