// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/Test.sol";
import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {DelegationManager} from "@eigenlayer-contracts/core/DelegationManager.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";

import {ERC20Minter} from "../test/mocks/ERC20Minter.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";
import {RouterFees} from "../script/RouterFees.sol";
import {AgentFactory} from "../src/6551/AgentFactory.sol";


contract CCIP_ForkTest_CompleteWithdrawal_Tests is BaseTestEnvironment, RouterFees {

    uint256 expiry;
    uint256 balanceOfReceiverBefore;
    uint256 balanceOfEigenAgent;

    // SenderHooks.WithdrawalTransferRootCommitted
    event WithdrawalTransferRootCommitted(
        bytes32 indexed, // withdrawalTransferRoot
        address indexed, //  withdrawer (eigenAgent)
        uint256, // amount
        address  // signer (agentOwner)
    );

    function setUp() public {
        // setup forked environments for L2 and L1 contracts
        setUpForkedEnvironment();
        // call params
        expiry = block.timestamp + 1 days;
    }

    /*
     *
     *
     *             Setup Eigenlayer State for CompleteWithdrawals
     *
     *
     */

    function setupL1State_DepositAndQueueWithdrawal(uint256 amount) public {

        vm.assume(amount <= 1 ether);
        vm.assume(amount > 0);

        //////////////////////////////////////////////////////
        /// L1: ReceiverCCIP -> EigenAgent -> Eigenlayer
        //////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        eigenAgent = agentFactory.getEigenAgent(bob); // should not exist yet
        require(address(eigenAgent) == address(0), "test assumes no EigenAgent yet");

        console.log("bob address:", bob);
        console.log("eigenAgent:", address(eigenAgent));
        console.log("---------------------------------------------");
        balanceOfEigenAgent = tokenL1.balanceOf(address(eigenAgent));
        balanceOfReceiverBefore = tokenL1.balanceOf(address(receiverContract));
        console.log("balanceOf(receiverContract):", balanceOfReceiverBefore);
        console.log("balanceOf(eigenAgent):", balanceOfEigenAgent);

        /////////////////////////////////////
        //// L1: Deposit with EigenAgent
        /////////////////////////////////////

        uint256 execNonce0 = 0; // no eigenAgent yet, execNonce is 0

        bytes memory messageWithSignature_D;
        {
            bytes memory depositMessage = encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_D = signMessageForEigenAgentExecution(
                bobKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager),
                depositMessage,
                execNonce0,
                expiry
            );
        }

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1), // CCIP-BnM token address on Eth Sepolia.
            amount: amount
        });

        vm.selectFork(ethForkId);
        {
            vm.expectEmit(true, false, true, false); // don't check topic[2] EigenAgent address
            emit AgentFactory.AgentCreated(bob, vm.addr(1111), 1);
            receiverContract.mockCCIPReceive(
                Client.Any2EVMMessage({
                    messageId: bytes32(0x0),
                    sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
                    sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
                    destTokenAmounts: destTokenAmounts, // Tokens and their amounts in their destination chain representation.
                    data: abi.encode(string(
                        messageWithSignature_D
                    )) // CCIP abi.encodes a string message when sending
                })
            );

            console.log("--------------- After Deposit -----------------");
            eigenAgent = agentFactory.getEigenAgent(bob);
            console.log("spawned eigenAgent: ", address(eigenAgent));

            require(
                tokenL1.balanceOf(address(receiverContract)) == (balanceOfReceiverBefore - amount),
                "receiverContract did not send tokens to EigenAgent after depositing"
            );
            console.log("balanceOf(receiverContract) after deposit:", tokenL1.balanceOf(address(receiverContract)));
            console.log("balanceOf(eigenAgent) after deposit:", tokenL1.balanceOf(address(eigenAgent)));
            uint256 eigenAgentShares = strategyManager.stakerStrategyShares(address(eigenAgent), strategy);
            console.log("eigenAgent shares after deposit:", eigenAgentShares);
            require(eigenAgentShares > 0, "eigenAgent should have >0 shares after deposit");
        }

        /////////////////////////////////////
        //// [L1] Queue Withdrawal with EigenAgent
        /////////////////////////////////////

        uint256 execNonce1 = eigenAgent.execNonce();

        bytes memory messageWithSignature_QW;
        {
            IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
            uint256[] memory sharesToWithdraw = new uint256[](1);
            strategiesToWithdraw[0] = strategy;
            sharesToWithdraw[0] = amount;

            IDelegationManager.QueuedWithdrawalParams[] memory QWPArray;
            QWPArray = new IDelegationManager.QueuedWithdrawalParams[](1);
            QWPArray[0] = IDelegationManager.QueuedWithdrawalParams({
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw,
                withdrawer: address(eigenAgent)
            });

            // create the queueWithdrawal message for Eigenlayer
            bytes memory withdrawalMessage = encodeQueueWithdrawalsMsg(
                QWPArray
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_QW = signMessageForEigenAgentExecution(
                bobKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager),
                withdrawalMessage,
                execNonce1,
                expiry
            );
        }

        vm.selectFork(ethForkId);
        {
            receiverContract.mockCCIPReceive(
                Client.Any2EVMMessage({
                    messageId: bytes32(uint256(9999)),
                    sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
                    sender: abi.encode(address(deployer)), // bytes: abi.decode(sender) if coming from an EVM chain.
                    destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging coins, just sending msg
                    data: abi.encode(string(
                        messageWithSignature_QW
                    ))
                })
            );

            console.log("--------------- After Queue Withdrawal -----------------");

            uint256 numWithdrawals = delegationManager.cumulativeWithdrawalsQueued(address(eigenAgent));
            require(numWithdrawals > 0, "must queueWithdrawals first before completeWithdrawals");

            console.log("balanceOf(receiver):", tokenL1.balanceOf(address(receiverContract)));
            console.log("balanceOf(eigenAgent):", tokenL1.balanceOf(address(eigenAgent)));

            uint256 eigenAgentSharesQW = strategyManager.stakerStrategyShares(address(eigenAgent), strategy);
            console.log("eigenAgent shares after queueWithdrawal:", eigenAgentSharesQW);
            require(eigenAgentSharesQW == 0, "eigenAgent should have 0 shares after queueWithdrawal");
        }
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_FullFlow_CompleteWithdrawal() public {

        uint256 amount = 0.003 ether;
        setupL1State_DepositAndQueueWithdrawal(amount);

        /////////////////////////////////////////////////////////////////
        //// [L1] Complete Queued Withdrawals
        /////////////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        uint32 startBlock = uint32(block.number);
        uint256 execNonce2 = eigenAgent.execNonce();
        IDelegationManager.Withdrawal memory withdrawal;
        {
            uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(bob);

            IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
            uint256[] memory sharesToWithdraw = new uint256[](1);
            strategiesToWithdraw[0] = strategy;
            sharesToWithdraw[0] = amount;

            withdrawal = IDelegationManager.Withdrawal({
                staker: address(eigenAgent),
                delegatedTo: delegationManager.delegatedTo(address(eigenAgent)),
                withdrawer: address(eigenAgent),
                nonce: withdrawalNonce,
                startBlock: startBlock,
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw
            });

        }
        bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);
        require(withdrawalRoot != 0, "withdrawal root missing, queueWithdrawal first");

        /////////////////////////////////////////////////////////////////
        //// 1. [L2] Send CompleteWithdrawals message to L2 Bridge
        /////////////////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        uint256 stakerBalanceOnL2Before = IERC20(BaseSepolia.BridgeToken).balanceOf(bob);

        bytes memory messageWithSignature_CW;
        {
            // create the completeWithdrawal message for Eigenlayer
            IERC20[] memory tokensToWithdraw = new IERC20[](1);
            tokensToWithdraw[0] = tokenL1;

            bytes memory completeWithdrawalMessage = encodeCompleteWithdrawalMsg(
                withdrawal,
                tokensToWithdraw,
                0, //middlewareTimesIndex,
                true // receiveAsTokens
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = signMessageForEigenAgentExecution(
                bobKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                address(delegationManager),
                completeWithdrawalMessage,
                execNonce2,
                expiry
            );
        }

        bytes32 withdrawalTransferRoot = calculateWithdrawalTransferRoot(
            withdrawalRoot,
            withdrawal.shares[0],
            bob
        );

        uint256 gasLimit = senderHooks.getGasLimitForFunctionSelector(
            IDelegationManager.completeQueuedWithdrawal.selector);

        vm.expectEmit(true, false, true, false);
        emit WithdrawalTransferRootCommitted(
            withdrawalTransferRoot,
            withdrawal.withdrawer, // withdrawer
            withdrawal.shares[0],
            bob // signer
        );
        senderContract.sendMessagePayNative{
            value: getRouterFeesL2(
                address(receiverContract),
                string(messageWithSignature_CW),
                address(tokenL2),
                0 ether,
                gasLimit
            )
        }(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_CW),
            address(tokenL2), // destination token
            0, // not sending tokens, just message
            0 // use default gasLimit for this function
        );

        /////////////////////////////////////////////////////////////////
        //// [Offchain] CCIP relays tokens and message to L1 bridge
        /////////////////////////////////////////////////////////////////

        /////////////////////////////////////////////////////////////////
        //// 2. [L1] Mock receiving CompleteWithdrawals message on L1 Bridge
        /////////////////////////////////////////////////////////////////

        // fork ethsepolia so ReceiverCCIP -> Router calls work
        vm.selectFork(ethForkId);

        vm.warp(block.timestamp + 120); // 120 seconds = 10 blocks (12second per block)
        vm.roll((block.timestamp + 120) / 12);

        // sender contract is forked from testnet, addr will differ
        vm.expectEmit(false, true, true, false);
        emit ReceiverCCIP.BridgingWithdrawalToL2(
            withdrawalTransferRoot,
            address(tokenL1),
            amount
        );
        // Mock L1 bridge receiving CCIP message and calling CompleteWithdrawal on Eigenlayer
        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                data: abi.encode(string(
                    messageWithSignature_CW
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );
        console.log("--------------- After Complete Withdrawal -----------------");

        // tokens in the ReceiverCCIP bridge contract
        console.log("balanceOf(receiverContract) after:", tokenL1.balanceOf(address(receiverContract)));
        console.log("balanceOf(eigenAgent) after:", tokenL1.balanceOf(address(eigenAgent)));
        console.log("balanceOf(restakingConnector) after:", tokenL1.balanceOf(address(restakingConnector)));
        console.log("balanceOf(router) after:", tokenL1.balanceOf(address(EthSepolia.Router)));
        require(
            tokenL1.balanceOf(address(receiverContract)) == (balanceOfReceiverBefore - amount),
            "receiverContract did not send tokens to L1 completeWithdrawal"
        );
        require(
            tokenL1.balanceOf(address(eigenAgent)) == 0,
            "EigenAgent did not send tokens to ReceiverCCIP after completeWithdrawal"
        );

        /////////////////////////////////////////////////////////////////
        //// [Offchain] CCIP relays tokens and message to L2 bridge
        /////////////////////////////////////////////////////////////////

        /////////////////////////////////////////////////////////////////
        //// 3. [L2] Mock receiving handleTransferToAgentOwner message from L1
        /////////////////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        // fundsTransfer info should be available
        ISenderHooks.FundsTransfer memory fundsTransfer = senderHooks.getFundsTransferCommitment(
            withdrawalTransferRoot
        );
        vm.assertEq(fundsTransfer.amount, amount);
        vm.assertEq(fundsTransfer.agentOwner, bob);

        // Mock SenderContract on L2 receiving the tokens and TransferToAgentOwner CCIP message from L1
        Client.EVMTokenAmount[] memory destTokenAmountsL2 = new Client.EVMTokenAmount[](1);
        destTokenAmountsL2[0] = Client.EVMTokenAmount({
            token: address(BaseSepolia.BridgeToken), // CCIP-BnM token address on L2
            amount: amount
        });
        senderContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(address(receiverContract)),
                data: abi.encode(string(
                    encodeTransferToAgentOwnerMsg(
                        withdrawalTransferRoot
                    )
                )), // CCIP abi.encodes a string message when sending
                destTokenAmounts: destTokenAmountsL2
            })
        );

        uint256 stakerBalanceOnL2After = IERC20(BaseSepolia.BridgeToken).balanceOf(address(bob));
        console.log("--------------- L2 After Bridge back -----------------");
        console.log("balanceOf(bob) on L2 before:", stakerBalanceOnL2Before);
        console.log("balanceOf(bob) on L2 after:", stakerBalanceOnL2After);

        require(
            (stakerBalanceOnL2Before + amount) == stakerBalanceOnL2After,
            "balanceOf(bob) on L2 should increase by amount after L2 -> L2 withdrawal"
        );

        /////////////////////////////////////////////////////////////////
        //// Test Attempts to re-use WithdrawalAgentOwnerRoots
        /////////////////////////////////////////////////////////////////

        // attempting to commit a spent withdrawalTransferRoot should fail on L2
        vm.expectRevert("SenderHooks._commitWithdrawalTransferRootInfo: TransferRoot already used");
        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_CW),
            address(BaseSepolia.BridgeToken), // destination token
            0, // not sending tokens, just message
            0 // use default gasLimit for this function
        );

        // attempting to re-use withdrawalTransferRoot from L1 should fail
        bytes memory messageWithdrawalReuse = encodeTransferToAgentOwnerMsg(
            calculateWithdrawalTransferRoot(
                withdrawalRoot,
                amount,
                bob
            )
        );
        vm.expectRevert("SenderHooks.handleTransferToAgentOwner: TransferRoot already used");
        senderContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(address(receiverContract)),
                data: abi.encode(string(
                    messageWithdrawalReuse
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );

        // fundsTransfer should be deleted after withdrawal completes
        fundsTransfer = senderHooks.getFundsTransferCommitment(withdrawalTransferRoot);
        vm.assertEq(fundsTransfer.amount, 0);
        vm.assertEq(fundsTransfer.agentOwner, address(0));

        // withdrawalTransferRoot should be spent now
        vm.assertEq(senderHooks.isTransferRootSpent(withdrawalTransferRoot), true);
    }

    /*
     *
     *
     *             Tests Multiple Token Withdrawals
     *
     *
     */

    function test_CompleteWithdrawals_MultipleTokensOnL1() public {

        vm.selectFork(ethForkId);

        ///////////////////////////////////////////////////////
        // Deploy new token3
        ///////////////////////////////////////////////////////
        IERC20 token3;
        IStrategy strategy3;
        {
            ProxyAdmin proxyAdmin = new ProxyAdmin();

            token3 = IERC20(address(
                new TransparentUpgradeableProxy(
                    address(new ERC20Minter()),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        ERC20Minter.initialize.selector,
                        "token3",
                        "TKN3"
                    )
                )
            ));

            ERC20Minter(address(token3)).mint(bob, 1 ether);
            ERC20Minter(address(token3)).mint(address(receiverContract), 1 ether);
        }

        ///////////////////////////////////////////////////////
        /// Deploy new Eigenlayer strategy for token3 and configure strategy
        ///////////////////////////////////////////////////////
        {
            // deploy new strategy for token3
            strategy3 = strategyFactory.deployNewStrategy(token3);
            // setStrategyWithdrawalDelayBlocks
            IStrategy[] memory strategies3 = new IStrategy[](1);
            strategies3[0] = strategy3;
            uint256[] memory withdrawalDelayBlocks = new uint256[](1);
            withdrawalDelayBlocks[0] = 1;

            vm.prank(deployer);
            DelegationManager(address(delegationManager)).setStrategyWithdrawalDelayBlocks(strategies3, withdrawalDelayBlocks);

            IStrategy[] memory strategiesToWhitelist = new IStrategy[](1);
            bool[] memory thirdPartyTransfersForbiddenValues = new bool[](1);

            strategiesToWhitelist[0] = strategy3;
            thirdPartyTransfersForbiddenValues[0] = false;

            vm.prank(deployer);
            strategyFactory.whitelistStrategies(strategiesToWhitelist, thirdPartyTransfersForbiddenValues);
        }

        vm.prank(deployer);
        eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(bob);

        ///////////////////////////////////
        // Deposit Token 1
        ///////////////////////////////////
        uint256 amount = 0.1 ether;
        bytes32 messageId1 = bytes32(abi.encode(0x123333444555));
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);

        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1),
            amount: amount
        });

        {
            uint256 execNonce0 = 0;
            receiverContract.mockCCIPReceive(
                Client.Any2EVMMessage({
                    messageId: messageId1,
                    sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
                    sender: abi.encode(deployer),
                    destTokenAmounts: destTokenAmounts,
                    data: abi.encode(string(
                        signMessageForEigenAgentExecution(
                            bobKey,
                            block.chainid,
                            address(strategyManager),
                            encodeDepositIntoStrategyMsg(
                                address(strategy),
                                address(tokenL1),
                                amount
                            ),
                            execNonce0,
                            expiry
                        )
                    ))
                })
            );
        }

        ///////////////////////////////////
        // Deposit Token 3
        ///////////////////////////////////
        {
            uint256 execNonce1 = 1;
            destTokenAmounts[0] = Client.EVMTokenAmount({
                token: address(token3),
                amount: amount
            });

            receiverContract.mockCCIPReceive(
                Client.Any2EVMMessage({
                    messageId: messageId1,
                    sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
                    sender: abi.encode(deployer),
                    destTokenAmounts: destTokenAmounts,
                    data: abi.encode(string(
                        signMessageForEigenAgentExecution(
                            bobKey,
                            block.chainid,
                            address(strategyManager),
                            encodeDepositIntoStrategyMsg(
                                address(strategy3),
                                address(token3),
                                amount
                            ),
                            execNonce1,
                            expiry
                        )
                    ))
                })
            );
        }

        /////////////////////////////////////
        //// Queue Withdrawal - Multiple Tokens
        /////////////////////////////////////

        uint256 execNonce2 = eigenAgent.execNonce();
        uint32 startBlock = uint32(block.number);

        bytes memory messageWithSignature_QW;
        {
            IStrategy[] memory strategiesToWithdraw = new IStrategy[](2);
            uint256[] memory sharesToWithdraw = new uint256[](2);
            strategiesToWithdraw[0] = strategy;
            strategiesToWithdraw[1] = strategy3;
            sharesToWithdraw[0] = amount;
            sharesToWithdraw[1] = amount;

            IDelegationManager.QueuedWithdrawalParams[] memory QWPArray;
            QWPArray = new IDelegationManager.QueuedWithdrawalParams[](1);
            QWPArray[0] = IDelegationManager.QueuedWithdrawalParams({
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw,
                withdrawer: address(eigenAgent)
            });

            messageWithSignature_QW = signMessageForEigenAgentExecution(
                bobKey,
                block.chainid,
                address(delegationManager),
                encodeQueueWithdrawalsMsg(QWPArray),
                execNonce2,
                expiry
            );
        }

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(address(deployer)),
                destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging coins
                data: abi.encode(string(
                    messageWithSignature_QW
                ))
            })
        );

        vm.warp(block.timestamp + 3600);
        vm.roll((block.timestamp + 3600)/12);

        /////////////////////////////////////
        //// Complete Withdrawal - Multiple Tokens
        /////////////////////////////////////
        IDelegationManager.Withdrawal memory withdrawal;
        {
            uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(bob);

            IStrategy[] memory strategiesToWithdraw = new IStrategy[](2);
            uint256[] memory sharesToWithdraw = new uint256[](2);
            strategiesToWithdraw[0] = strategy;
            strategiesToWithdraw[1] = strategy3;
            sharesToWithdraw[0] = amount;
            sharesToWithdraw[1] = amount;

            withdrawal = IDelegationManager.Withdrawal({
                staker: address(eigenAgent),
                delegatedTo: delegationManager.delegatedTo(address(eigenAgent)),
                withdrawer: address(eigenAgent),
                nonce: withdrawalNonce,
                startBlock: startBlock,
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw
            });
        }

        uint256 execNonce3 = eigenAgent.execNonce();
        bytes memory messageWithSignature_CW;
        {
            IERC20[] memory tokensToWithdraw = new IERC20[](2);
            tokensToWithdraw[0] = tokenL1;
            tokensToWithdraw[1] = token3;

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature_CW = signMessageForEigenAgentExecution(
                bobKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(delegationManager),
                encodeCompleteWithdrawalMsg(
                    withdrawal,
                    tokensToWithdraw,
                    0, //middlewareTimesIndex,
                    true // receiveAsTokens
                ),
                execNonce3,
                expiry
            );
        }

        uint256 bobBalanceBefore = token3.balanceOf(bob);

        vm.expectEmit(false, true, true, false);
        emit ReceiverCCIP.BridgingWithdrawalToL2(
            calculateWithdrawalTransferRoot(
                delegationManager.calculateWithdrawalRoot(withdrawal),
                withdrawal.shares[0], // shares of tokenL1, not token3
                bob
            ),
            address(tokenL1),
            amount
        );
        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                data: abi.encode(string(
                    messageWithSignature_CW
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );

        require(
            token3.balanceOf(bob) == bobBalanceBefore + amount,
            "Bob should have received some token3 on L1"
        );
    }

}
