// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {OwnableUpgradeable} from "@openzeppelin-v5-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-v5-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-v5-contracts/proxy/transparent/ProxyAdmin.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {TestERC20} from "./mocks/TestERC20.sol";
import {AgentFactory} from "../src/6551/AgentFactory.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";

import {console} from "forge-std/Script.sol";


contract UnitTests_ReceiverRestakingConnector is BaseTestEnvironment {

    error AddressZero(string msg);
    error CallerNotWhitelisted(string reason);
    error SignatureInvalid(string reason);
    error AlreadyRefunded(uint256 amount);
    error WithdrawalExceedsBalance(uint256 amount, uint256 currentBalance);

    uint256 expiry;
    uint256 execNonce0;

    function setUp() public {

        setUpLocalEnvironment();

        expiry = block.timestamp + 1 hours;
        execNonce0 = 0;

        vm.prank(deployer);
        eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);
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

        vm.expectRevert(abi.encodeWithSelector(
            OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
            address(this)
        ));
        receiverContract.setRestakingConnector(IRestakingConnector(address(0)));

        vm.expectRevert(abi.encodeWithSelector(
            OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
            address(this)
        ));
        receiverContract.setSenderContractL2(address(senderContract));

        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(AddressZero.selector,
            "SenderContract on L2 cannot be address(0)"));
        receiverContract.setSenderContractL2(address(0));

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

        ReceiverCCIP receiverImpl = new ReceiverCCIP(EthSepolia.Router);
        ProxyAdmin pa = new ProxyAdmin(address(this));

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
        ProxyAdmin pa = new ProxyAdmin(address(this));

        vm.expectRevert(
            abi.encodeWithSelector(AddressZero.selector, "AgentFactory cannot be address(0)")
        );
        new TransparentUpgradeableProxy(
            address(restakingImpl),
            address(pa),
            abi.encodeWithSelector(
                RestakingConnector.initialize.selector,
                address(0),
                address(1),
                address(2)
            )
        );
    }

    function test_HandleCustomErrorForDeposits_InvalidTargetContract() public {

        uint256 execNonce = 0;
        uint256 expiryShort = block.timestamp + 60 seconds;
        uint256 amount = 0.1 ether;

        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            bobKey,
            address(eigenAgent),
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
        receiverContract.withdrawTokenForMessageId(messageId1, bob, address(tokenL1), 0.1 ether);

        vm.assertEq(tokenL1.balanceOf(bob), 0.1 ether);

        // after refund, show original error message instead
        vm.expectRevert(abi.encodeWithSelector(AlreadyRefunded.selector, 0.1 ether));
        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    function test_HandleCustomError_CallerNotAllowed() public {

        uint256 execNonce = 0;
        uint256 expiryShort = block.timestamp + 60 seconds;
        uint256 amount = 0.1 ether;

        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            bobKey,
            address(eigenAgent),
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

        vm.expectRevert(abi.encodeWithSelector(CallerNotWhitelisted.selector, "EigenAgent6551: caller not allowed"));
        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    function test_ReceiverL1_HandleCustomDepositError_BubbleErrorsUp() public {

        uint256 execNonce = 0;
        // should revert with EigenAgentExecutionError(signer, expiry)
        address invalidEigenlayerStrategy = vm.addr(4444);
        // make expiryShort to test refund on expiry feature
        uint256 expiryShort = block.timestamp + 60 seconds;
        uint256 amount = 0.1 ether;

        vm.startPrank(deployer);
        IEigenAgent6551 eigenAgentBob = agentFactory.spawnEigenAgentOnlyOwner(bob);
        vm.stopPrank();

        console.log("111111 address(eigenAgentBob): ", address(eigenAgentBob));
        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            bobKey, // sign with Bob's key
            address(eigenAgentBob),
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
        bytes32 domainSeparator = eigenAgentBob.domainSeparator(block.chainid);
        console.log("222222 domainSeparator: ");
        console.logBytes32(domainSeparator);

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1),
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

    function test_ReceiverL1_HandleCustomDepositError_DepositOnlyOneToken() public {

        uint256 execNonce = 0;
        // should revert with EigenAgentExecutionError(signer, expiry)
        address invalidEigenlayerStrategy = vm.addr(4444);
        // make expiryShort to test refund on expiry feature
        uint256 expiryShort = block.timestamp + 60 seconds;
        uint256 amount = 0.1 ether;

        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            bobKey,
            address(eigenAgent),
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

        TestERC20 token2 = new TestERC20("token2", "TKN2");

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](2);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1),
            amount: amount
        });
        // mock a second token to trigger error
        destTokenAmounts[1] = Client.EVMTokenAmount({
            token: address(token2),
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
                "DepositIntoStrategy only handles one token at a time",
                "Manually execute to refund after timestamp:",
                expiryShort
            )
        );
        receiverContract.mockCCIPReceive(any2EvmMessage);
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
            address(agentFactory.getEigenAgent(deployer)) == address(eigenAgent),
            "Deployer should not have minted a new EigenAgent"
        );
    }

    function test_ReceiverL1_MintEigenAgent_OnlyCallableByReceiver() public {

        bytes memory mintEigenAgentMessageBob = encodeMintEigenAgentMsg(bob);
        bytes memory messageCCIP = abi.encode(string(mintEigenAgentMessageBob));

        vm.expectRevert("not called by ReceiverCCIP");
        restakingConnector.mintEigenAgent(messageCCIP);

        vm.prank(address(receiverContract));
        restakingConnector.mintEigenAgent(messageCCIP);
    }

    function test_ReceiverContractL1_CanReceiveEther() public {
        vm.deal(deployer, 0.1 ether);
        vm.prank(deployer);
        (bool success, ) = address(senderContract).call{value: 0.1 ether}("");
        vm.assertTrue(success);
    }

    function test_ReceiverContractL1_SetAndGet_QueueWithdrawalBlock() public {

        vm.expectRevert("Not admin or owner");
        restakingConnector.setQueueWithdrawalBlock(deployer, 22, 9999);

        vm.prank(deployer);
        restakingConnector.setQueueWithdrawalBlock(deployer, 22, 9999);

        uint256 withdrawalBlock = restakingConnector.getQueueWithdrawalBlock(deployer, 22);
        vm.assertEq(withdrawalBlock, 9999);
    }


    function test_RestakingConnector_SetAndGet_AgentFactory() public {
        vm.expectRevert(abi.encodeWithSelector(
            OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
            address(this)
        ));
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

    function test_RestakingConnector_SetAndGet_EigenlayerContracts() public {
        vm.expectRevert(abi.encodeWithSelector(
            OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
            address(this)
        ));
        restakingConnector.setEigenlayerContracts(
            delegationManager,
            strategyManager,
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
                rewardsCoordinator
            );

            vm.expectRevert(
                abi.encodeWithSelector(AddressZero.selector, "_strategyManager cannot be address(0)")
            );
            restakingConnector.setEigenlayerContracts(
                delegationManager,
                IStrategyManager(address(0)),
                rewardsCoordinator
            );

            vm.expectRevert(
                abi.encodeWithSelector(AddressZero.selector, "_rewardsCoordinator cannot be address(0)")
            );
            restakingConnector.setEigenlayerContracts(
                delegationManager,
                strategyManager,
                IRewardsCoordinator(address(0))
            );


            restakingConnector.setEigenlayerContracts(
                delegationManager,
                strategyManager,
                rewardsCoordinator
            );

            (
                IDelegationManager _delegationManager,
                IStrategyManager _strategyManager,
                IRewardsCoordinator _rewardsCoordinator
            ) = restakingConnector.getEigenlayerContracts();

            vm.assertEq(address(delegationManager), address(_delegationManager));
            vm.assertEq(address(strategyManager), address(_strategyManager));
            vm.assertEq(address(rewardsCoordinator), address(_rewardsCoordinator));
        }
        vm.stopBroadcast();
    }

    function test_RestakingConnector_SetAndGet_GasLimits() public {

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
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelectorL1(0xffeeaabb), 200_000);

        // gas limits should be set
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelectorL1(functionSelectors[0]), 1_000_000);
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelectorL1(functionSelectors[1]), 800_000);

        vm.stopBroadcast();
    }

    function test_ReceiverL1_dispatchMessageToEigenAgent_InternalCallsOnly(address user) public {

        vm.assume(user != address(receiverContract));
        vm.assume(user != deployer);

        vm.prank(user);

        vm.expectRevert("not called by ReceiverCCIP");
        restakingConnector.dispatchMessageToEigenAgent(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                data: abi.encode(string(
                    encodeMintEigenAgentMsg(deployer)
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );

        vm.prank(address(receiverContract));
        restakingConnector.dispatchMessageToEigenAgent(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                data: abi.encode(string(
                    encodeMintEigenAgentMsg(deployer)
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );
    }

    function test_ReceiverContractL1_WithdrawTokenForMessageId_BalanceMatches() public {

        bytes32 messageId = bytes32(abi.encode(1,2,3));

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(
            OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
            bob
        ));
        receiverContract.withdrawTokenForMessageId(messageId, bob, address(tokenL1), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(WithdrawalExceedsBalance.selector, 2 ether, 1 ether));
        vm.prank(deployer);
        receiverContract.withdrawTokenForMessageId(messageId, bob, address(tokenL1), 2 ether);

        vm.prank(deployer);
        receiverContract.withdrawTokenForMessageId(messageId, bob, address(tokenL1), 0.3 ether);

        vm.assertEq(
            receiverContract.amountRefunded(messageId, address(tokenL1)),
            0.3 ether
        );
        vm.assertEq(tokenL1.balanceOf(bob), 0.3 ether);

    }

    function test_ReceiverContractL1_WithdrawTokenForMessageId_AlreadyRefunded() public {

        bytes32 messageId = bytes32(abi.encode(1,2,3));
        uint256 refundAmount = 0.2 ether;

        // refund
        vm.prank(deployer);
        receiverContract.withdrawTokenForMessageId(messageId, bob, address(tokenL1), refundAmount);

        vm.assertEq(receiverContract.amountRefunded(messageId, address(tokenL1)), refundAmount);
        vm.assertEq(tokenL1.balanceOf(bob), refundAmount);

        // revert when trying to refund again
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(AlreadyRefunded.selector, refundAmount));
        receiverContract.withdrawTokenForMessageId(
            messageId,
            bob,
            address(tokenL1),
            0.1 ether
        );
    }

    function test_RestakingConnector_SetBridgeTokens() public {

        ProxyAdmin proxyAdmin = new ProxyAdmin(address(this));

        address _bridgeTokenL1 = vm.addr(1001);
        address _bridgeTokenL2 = vm.addr(2002);

        RestakingConnector rcImpl = new RestakingConnector();

        vm.expectRevert(abi.encodeWithSelector(AddressZero.selector, "_bridgeTokenL1 cannot be address(0)"));
        new TransparentUpgradeableProxy(
            address(rcImpl ),
            address(proxyAdmin),
            abi.encodeWithSelector(
                RestakingConnector.initialize.selector,
                agentFactory,
                address(0),
                _bridgeTokenL2
            )
        );

        vm.expectRevert(abi.encodeWithSelector(AddressZero.selector, "_bridgeTokenL2 cannot be address(0)"));
        new TransparentUpgradeableProxy(
            address(rcImpl ),
            address(proxyAdmin),
            abi.encodeWithSelector(
                RestakingConnector.initialize.selector,
                agentFactory,
                _bridgeTokenL1,
                address(0)
            )
        );

        vm.prank(deployer);
        RestakingConnector rc = RestakingConnector(address(
            new TransparentUpgradeableProxy(
                address(rcImpl ),
                address(proxyAdmin),
                abi.encodeWithSelector(
                    RestakingConnector.initialize.selector,
                    agentFactory,
                    _bridgeTokenL1,
                    _bridgeTokenL2
                )
            )
        ));

        vm.startBroadcast(bob);
        {
        vm.expectRevert(abi.encodeWithSelector(
            OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
            bob
        ));
            rc.setBridgeTokens(_bridgeTokenL1, _bridgeTokenL2);
        }
        vm.stopBroadcast();

        vm.startBroadcast(deployer);
        {
            vm.expectRevert(abi.encodeWithSelector(AddressZero.selector, "_bridgeTokenL1 cannot be address(0)"));
            rc.setBridgeTokens(address(0), _bridgeTokenL2);

            vm.expectRevert(abi.encodeWithSelector(AddressZero.selector, "_bridgeTokenL2 cannot be address(0)"));
            rc.setBridgeTokens(_bridgeTokenL1, address(0));

            rc.setBridgeTokens(_bridgeTokenL1, _bridgeTokenL2);
            vm.assertEq(rc.bridgeTokensL1toL2(_bridgeTokenL1), _bridgeTokenL2);

            rc.clearBridgeTokens(_bridgeTokenL1);
            vm.assertEq(rc.bridgeTokensL1toL2(_bridgeTokenL1), address(0));
        }
        vm.stopBroadcast();
    }

}
