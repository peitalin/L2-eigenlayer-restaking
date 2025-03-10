// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {OwnableUpgradeable} from "@openzeppelin-v5-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-v5-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-v5-contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin-v4-contracts/token/ERC20/IERC20.sol";

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "@eigenlayer-contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";

import {TestERC20} from "./mocks/TestERC20.sol";
import {AgentFactory} from "../src/6551/AgentFactory.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {RestakingConnectorUtils} from "../src/RestakingConnectorUtils.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
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
    address sender = address(receiverContract);

    // Mock tokens
    IERC20 tokenA = IERC20(address(0x1aa));
    IERC20 tokenB = IERC20(address(0x2bb));
    IERC20 tokenC = IERC20(address(0x3cc));
    IERC20 tokenD = IERC20(address(0x4dd));

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
            sender: abi.encode(sender),
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

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1),
            amount: amount
        });
        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0x0),
            sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
            sender: abi.encode(sender),
            destTokenAmounts: destTokenAmounts,
            data: abi.encode(string(
                messageWithSignature
            ))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IRestakingConnector.ExecutionErrorRefundAfterExpiry.selector,
                "StrategyNotWhitelisted()",
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
            sender: abi.encode(sender),
            destTokenAmounts: destTokenAmounts,
            data: abi.encode(string(
                messageWithSignature
            ))
        });

        vm.expectRevert("DepositIntoStrategy only handles one token at a time");
        receiverContract.mockCCIPReceive(any2EvmMessage);
    }

    function test_ReceiverL1_MintEigenAgent2() public {

        bytes memory mintEigenAgentMessageBob = encodeMintEigenAgentMsg(bob);

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
                sender: abi.encode(sender),
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
                sender: abi.encode(sender),
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
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelectorL1(0xffeeaabb, 0), 200_000);

        // gas limits should be set
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelectorL1(functionSelectors[0], 0), 1_000_000);
        vm.assertEq(restakingConnector.getGasLimitForFunctionSelectorL1(functionSelectors[1], 0), 800_000);

        vm.stopBroadcast();
    }

    function test_RestakingConnector_increaseGasLimitForEachExtraToken() public {

        bytes4 handleTransferToAgentOwner = ISenderHooks.handleTransferToAgentOwner.selector;

        uint256 gasLimit = restakingConnector.getGasLimitForFunctionSelectorL1(handleTransferToAgentOwner, 0);
        vm.assertEq(gasLimit, 300_000);

        gasLimit = restakingConnector.getGasLimitForFunctionSelectorL1(handleTransferToAgentOwner, 1);
        vm.assertEq(gasLimit, 300_000 + 100_000 * 0);

        gasLimit = restakingConnector.getGasLimitForFunctionSelectorL1(handleTransferToAgentOwner, 2);
        vm.assertEq(gasLimit, 300_000 + 100_000 * 1);

        gasLimit = restakingConnector.getGasLimitForFunctionSelectorL1(handleTransferToAgentOwner, 3);
        vm.assertEq(gasLimit, 300_000 + 100_000 * 2);

        gasLimit = restakingConnector.getGasLimitForFunctionSelectorL1(handleTransferToAgentOwner, 4);
        vm.assertEq(gasLimit, 300_000 + 100_000 * 3);

        gasLimit = restakingConnector.getGasLimitForFunctionSelectorL1(handleTransferToAgentOwner, 5);
        vm.assertEq(gasLimit, 300_000 + 100_000 * 4);
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
                sender: abi.encode(sender),
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
                sender: abi.encode(sender),
                data: abi.encode(string(
                    encodeMintEigenAgentMsg(deployer)
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
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


    function test_GetUniqueTokens_AllUnique() public view {

        IERC20[] memory inputTokens = new IERC20[](4);
        inputTokens[0] = IERC20(address(tokenA));
        inputTokens[1] = IERC20(address(tokenB));
        inputTokens[2] = IERC20(address(tokenC));
        inputTokens[3] = IERC20(address(tokenD));

        IERC20[] memory uniqueTokens = RestakingConnectorUtils.getUniqueTokens(inputTokens);

        assertEq(uniqueTokens.length, 4, "Should return 4 unique tokens");

        // Verify all tokens are in the result
        bool foundA = false;
        bool foundB = false;
        bool foundC = false;
        bool foundD = false;

        for (uint i = 0; i < uniqueTokens.length; i++) {
            if (address(uniqueTokens[i]) == address(tokenA)) foundA = true;
            if (address(uniqueTokens[i]) == address(tokenB)) foundB = true;
            if (address(uniqueTokens[i]) == address(tokenC)) foundC = true;
            if (address(uniqueTokens[i]) == address(tokenD)) foundD = true;
        }

        assertTrue(foundA, "Token A should be in result");
        assertTrue(foundB, "Token B should be in result");
        assertTrue(foundC, "Token C should be in result");
        assertTrue(foundD, "Token D should be in result");
    }

    function test_GetUniqueTokens_IERC20_WithDuplicates() public view {

        IERC20[] memory inputTokens = new IERC20[](7);
        inputTokens[0] = IERC20(address(tokenA));
        inputTokens[1] = IERC20(address(tokenB));
        inputTokens[2] = IERC20(address(tokenA)); // Duplicate
        inputTokens[3] = IERC20(address(tokenC));
        inputTokens[4] = IERC20(address(tokenB)); // Duplicate
        inputTokens[5] = IERC20(address(tokenD));
        inputTokens[6] = IERC20(address(tokenC)); // Duplicate

        IERC20[] memory uniqueTokens = RestakingConnectorUtils.getUniqueTokens(inputTokens);

        assertEq(uniqueTokens.length, 4, "Should return 4 unique tokens, removing 3 duplicates");

        // Verify all tokens are in the result exactly once
        bool foundA = false;
        bool foundB = false;
        bool foundC = false;
        bool foundD = false;
        for (uint i = 0; i < uniqueTokens.length; i++) {
            if (address(uniqueTokens[i]) == address(tokenA)) {
                assertFalse(foundA, "Token A should only appear once");
                foundA = true;
            }
            if (address(uniqueTokens[i]) == address(tokenB)) {
                assertFalse(foundB, "Token B should only appear once");
                foundB = true;
            }
            if (address(uniqueTokens[i]) == address(tokenC)) {
                assertFalse(foundC, "Token C should only appear once");
                foundC = true;
            }
            if (address(uniqueTokens[i]) == address(tokenD)) {
                assertFalse(foundD, "Token D should only appear once");
                foundD = true;
            }
        }
        assertTrue(foundA, "Token A should be in result");
        assertTrue(foundB, "Token B should be in result");
        assertTrue(foundC, "Token C should be in result");
        assertTrue(foundD, "Token D should be in result");
    }

    function test_GetUniqueTokens_IERC20_EmptyArray() public pure {
        IERC20[] memory inputTokens = new IERC20[](0);

        IERC20[] memory uniqueTokens = RestakingConnectorUtils.getUniqueTokens(inputTokens);

        assertEq(uniqueTokens.length, 0, "Should return empty array");
    }

    function test_GetUniqueTokens_IERC20_SingleToken() public view {
        IERC20[] memory inputTokens = new IERC20[](1);
        inputTokens[0] = IERC20(address(tokenA));

        IERC20[] memory uniqueTokens = RestakingConnectorUtils.getUniqueTokens(inputTokens);

        assertEq(uniqueTokens.length, 1, "Should return 1 token");
        assertEq(address(uniqueTokens[0]), address(tokenA), "Should return Token A");
    }

    function test_GetUniqueTokens_IERC20_AllDuplicates() public view {
        IERC20[] memory inputTokens = new IERC20[](3);
        inputTokens[0] = IERC20(address(tokenA));
        inputTokens[1] = IERC20(address(tokenA));
        inputTokens[2] = IERC20(address(tokenA));

        IERC20[] memory uniqueTokens = RestakingConnectorUtils.getUniqueTokens(inputTokens);

        assertEq(uniqueTokens.length, 1, "Should return 1 unique token");
        assertEq(address(uniqueTokens[0]), address(tokenA), "Should return Token A");
    }

    function test_GetUniqueTokens_TokenTreeMerkleLeaf_AllUnique() public view {

        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[] memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](4);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenA)),
            cumulativeEarnings: 1
        });
        tokenLeaves[1] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenB)),
            cumulativeEarnings: 1
        });
        tokenLeaves[2] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenC)),
            cumulativeEarnings: 1
        });
        tokenLeaves[3] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenD)),
            cumulativeEarnings: 1
        });

        IERC20[] memory uniqueTokens = RestakingConnectorUtils.getUniqueTokens(tokenLeaves);

        assertEq(uniqueTokens.length, 4, "Should return 4 unique tokens");

        // Verify all tokens are in the result
        bool foundA = false;
        bool foundB = false;
        bool foundC = false;
        bool foundD = false;

        for (uint i = 0; i < uniqueTokens.length; i++) {
            if (address(uniqueTokens[i]) == address(tokenA)) foundA = true;
            if (address(uniqueTokens[i]) == address(tokenB)) foundB = true;
            if (address(uniqueTokens[i]) == address(tokenC)) foundC = true;
            if (address(uniqueTokens[i]) == address(tokenD)) foundD = true;
        }

        assertTrue(foundA, "Token A should be in result");
        assertTrue(foundB, "Token B should be in result");
        assertTrue(foundC, "Token C should be in result");
        assertTrue(foundD, "Token D should be in result");
    }

    function test_GetUniqueTokens_TokenTreeMerkleLeaf_WithDuplicates() public view {

        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[] memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](7);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenA)),
            cumulativeEarnings: 1
        });
        tokenLeaves[1] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenB)),
            cumulativeEarnings: 1
        });
        tokenLeaves[2] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenA)), // Duplicate
            cumulativeEarnings: 1
        });
        tokenLeaves[3] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenC)),
            cumulativeEarnings: 1
        });
        tokenLeaves[4] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenB)), // Duplicate
            cumulativeEarnings: 1
        });
        tokenLeaves[5] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenD)),
            cumulativeEarnings: 1
        });
        tokenLeaves[6] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenC)), // Duplicate
            cumulativeEarnings: 1
        });

        IERC20[] memory uniqueTokens = RestakingConnectorUtils.getUniqueTokens(tokenLeaves);

        assertEq(uniqueTokens.length, 4, "Should return 4 unique tokens, removing 3 duplicates");

        // Verify all tokens are in the result exactly once
        bool foundA = false;
        bool foundB = false;
        bool foundC = false;
        bool foundD = false;
        for (uint i = 0; i < uniqueTokens.length; i++) {
            if (address(uniqueTokens[i]) == address(tokenA)) {
                assertFalse(foundA, "Token A should only appear once");
                foundA = true;
            }
            if (address(uniqueTokens[i]) == address(tokenB)) {
                assertFalse(foundB, "Token B should only appear once");
                foundB = true;
            }
            if (address(uniqueTokens[i]) == address(tokenC)) {
                assertFalse(foundC, "Token C should only appear once");
                foundC = true;
            }
            if (address(uniqueTokens[i]) == address(tokenD)) {
                assertFalse(foundD, "Token D should only appear once");
                foundD = true;
            }
        }
        assertTrue(foundA, "Token A should be in result");
        assertTrue(foundB, "Token B should be in result");
        assertTrue(foundC, "Token C should be in result");
        assertTrue(foundD, "Token D should be in result");
    }

    function test_GetUniqueTokens_TokenTreeMerkleLeaf_EmptyArray() public pure {
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[] memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](0);

        IERC20[] memory uniqueTokens = RestakingConnectorUtils.getUniqueTokens(tokenLeaves);

        assertEq(uniqueTokens.length, 0, "Should return empty array");
    }

    function test_GetUniqueTokens_SingleToken() public view {
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[] memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenA)),
            cumulativeEarnings: 1
        });

        IERC20[] memory uniqueTokens = RestakingConnectorUtils.getUniqueTokens(tokenLeaves);

        assertEq(uniqueTokens.length, 1, "Should return 1 token");
        assertEq(address(uniqueTokens[0]), address(tokenA), "Should return Token A");
    }

    function test_GetUniqueTokens_TokenTreeMerkleLeaf_AllDuplicates() public view {
        IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[] memory tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](3);
        tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenA)),
            cumulativeEarnings: 1
        });
        tokenLeaves[1] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenA)),
            cumulativeEarnings: 1
        });
        tokenLeaves[2] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(address(tokenA)),
            cumulativeEarnings: 1
        });

        IERC20[] memory uniqueTokens = RestakingConnectorUtils.getUniqueTokens(tokenLeaves);

        assertEq(uniqueTokens.length, 1, "Should return 1 unique token");
        assertEq(address(uniqueTokens[0]), address(tokenA), "Should return Token A");
    }

    function test_BuildCCIPMessage_SenderMustBeReceiverCCIPError() public {
        // Set up test data
        address invalidSender = address(0x123);
        address l2Sender = receiverContract.getSenderContractL2();
        Client.EVMTokenAmount[] memory tokens = new Client.EVMTokenAmount[](0);

        // Attempt to build message from unauthorized sender
        vm.prank(invalidSender);
        vm.expectRevert(abi.encodeWithSelector(
            ReceiverCCIP.SenderMustBeReceiverCCIP.selector
        ));
        // Trigger _buildCCIPMessage internal call by attempting to send message
        receiverContract.sendMessagePayNative(
            BaseSepolia.ChainSelector, // destination chain
            l2Sender, // receiver must be L2 sender contract
            string(encodeTransferToAgentOwnerMsg(deployer)), // test message
            tokens,
            0 // gas limit
        );
        // TransferToAgnetOwner messages should be sendable when
        // msg.sender is the receiver contract.
        // This is covered in fork tests such as
        // CCIP_ForkTest3_CompleteWithdrawal.t.sol which has access
        // to the Router.getFee function. Otherwise calling
        // receiverContract.sendMessagePayNative() will fail with
        // a Router.getFee error in local unit tests.
    }
}