// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin-v5-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-v5-contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin-v4-contracts/token/ERC20/IERC20.sol";
import {IBurnMintERC20} from "@chainlink/shared/token/ERC20/IBurnMintERC20.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {ERC20Minter} from "./mocks/ERC20Minter.sol";

import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorEvents} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {Merkle} from "@eigenlayer-contracts/libraries/Merkle.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";
import {RouterFees} from "../script/RouterFees.sol";
import {AgentFactory} from "../src/6551/AgentFactory.sol";
import {RewardsUtils} from "../script/9_submitRewards.s.sol";


contract CCIP_ForkTest_RewardsProcessClaim_Tests is BaseTestEnvironment, RouterFees {

    // SenderHooks.RewardsTransferRootCommitted
    event RewardsTransferRootCommitted(
        bytes32 indexed rewardsTransferRoot,
        address agentOwner
    );

    event SendingFundsToAgentOwner(address indexed, uint256 indexed);

    event RewardsClaimed(
        bytes32 root,
        address indexed earner,
        address indexed claimer,
        address indexed recipient,
        IERC20 token,
        uint256 claimedAmount
    );

    RewardsUtils.TestRewardsTree public tree;
    bytes32[] leaves;
    address[4] EARNERS;
    uint256[4] REWARDS_AMOUNTS1;
    uint256[4] REWARDS_AMOUNTS2;
    IERC20 memecoin;

    uint256 execNonce;
    uint256 expiry;
    uint256 routerFees;

    uint256 rewardsAmount;
    address rewardsToken;

    uint32 secondsInWeek;
    uint32 timeNow;
    uint32 startOfTheWeek;
    uint32 startOfLastWeek;

    function setUp() public {
        // setup forked environments for L2 and L1 contracts
        setUpForkedEnvironment();
        vm.selectFork(ethForkId);

        vm.startBroadcast(deployer);
        eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);

        EARNERS = [
            address(eigenAgent),
            bob,
            charlie,
            dani
        ];
        REWARDS_AMOUNTS1 = [
            0.11 ether,
            0.12 ether,
            0.13 ether,
            0.14 ether
        ];
        REWARDS_AMOUNTS2 = [
            0.21 ether,
            0.22 ether,
            0.23 ether,
            0.24 ether
        ];

        // Create a second memecoin ERC20 token for multi-token rewards claims
        memecoin = IERC20(payable(address(
            new TransparentUpgradeableProxy(
                address(new ERC20Minter()),
                address(deployer),
                abi.encodeWithSelector(
                    ERC20Minter.initialize.selector,
                    "token2",
                    "TKN2"
                )
            )))
        );
        // Send RewardsCoordinator some tokens for rewards claims
        ERC20Minter(address(memecoin)).mint(address(rewardsCoordinator), 1 ether);
        vm.stopBroadcast();

       // let timeNow be 2 weeks from now for local tests
        vm.warp(block.timestamp + 1 weeks);
        secondsInWeek = 604800;
        // start of the rewards week
        startOfTheWeek = uint32(block.timestamp) - (uint32(block.timestamp) % secondsInWeek);
        startOfLastWeek = startOfTheWeek - 1 weeks;
        // timeNow should be more than 1 week from startOfTheWeek
        timeNow = startOfTheWeek + 1 days;

        require(startOfTheWeek % secondsInWeek == 0, "startOfTheWeek is not a multiple of secondsInWeek");
        require(startOfLastWeek % secondsInWeek == 0, "startOfLastWeek is not a multiple of secondsInWeek");
    }

    /*
     *
     *
     *             Setup Eigenlayer State for Rewards Claims
     *
     *
     */

    function setupRewardsMerkleTree() internal returns (RewardsUtils.TestRewardsTree memory tree) {

        // Rewind back to the start of last week:
        vm.warp(startOfLastWeek);
        // NOTE: we need to rewind time otherwise fork tests with CCIP's router do not work.
        // CCIP router's are time-sensitive when fetching fees/prices and fails if warping into future.

        //// Setup reward merkle roots with mock users
        tree = RewardsUtils.createEarnerTreeTwoTokens(
            rewardsCoordinator,
            EARNERS,
            address(tokenL1),
            address(memecoin),
            REWARDS_AMOUNTS1,
            REWARDS_AMOUNTS2
        );

        // validate earners claims, and see if their proofs are ok.
        RewardsUtils.generateClaimProof(tree, 0);
        RewardsUtils.generateClaimProof(tree, 1);
        RewardsUtils.generateClaimProof(tree, 2);
        RewardsUtils.generateClaimProof(tree, 3);

        uint32 startTimestamp = startOfLastWeek; // startTimestamp, must be a multiple of 604800 (7 days)
        uint32 duration = 604800; // duration, must be a multiple of 604800

        uint32 rewardsCalculationEndTimestamp = startOfLastWeek + duration;
        vm.warp(startOfLastWeek + duration + 1 hours);
        // wait past rewardsCalculation End Timestamp, then submit root

		/////////////////////////////////////////////////////////////////
		// Submit Rewards Merkle Root
		/////////////////////////////////////////////////////////////////
        vm.prank(deployer);

        uint32 rootIndex = 0; // first rewards root submitted
        vm.expectEmit(true, true, true, false);
        emit IRewardsCoordinatorEvents.DistributionRootSubmitted(rootIndex, tree.root, rewardsCalculationEndTimestamp, 0);
        rewardsCoordinator.submitRoot(tree.root, rewardsCalculationEndTimestamp);

        // There should be 1 DistributionRoot now.
        vm.assertTrue(rewardsCoordinator.getDistributionRootsLength() == 1);

        // Send RewardsCoordinator some tokens for rewards claims
        vm.prank(deployer);
        IERC20(address(tokenL1)).transfer(address(rewardsCoordinator), 1 ether);

		// Fast forward to present time
        vm.warp(timeNow + 7 days);

        return tree;
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_FullFlow_ProcessClaimRewards() public {

        vm.selectFork(ethForkId);

        tree = setupRewardsMerkleTree();

        uint32 earnerIndex = 0;
        bytes memory proof = RewardsUtils.generateClaimProof(tree, earnerIndex);

        /////////////////////////////////////////////////////////////////
        // Create claim for Alice: earners[0], amounts[0]
		/////////////////////////////////////////////////////////////////
        IRewardsCoordinator.RewardsMerkleClaim memory claim = RewardsUtils.createClaimTwoTokens(
            rewardsCoordinator,
            0, // currentDistRootIndex
            EARNERS[earnerIndex],
            earnerIndex,
            proof,
            address(tokenL1),
            address(memecoin),
            REWARDS_AMOUNTS1[earnerIndex],
            REWARDS_AMOUNTS2[earnerIndex]
        );

		require(rewardsCoordinator.checkClaim(claim), "checkClaim(claim) failed, invalid claim.");

        execNonce = 0;
        expiry = block.timestamp + 1 hours;

        // sign the message for EigenAgent to execute Eigenlayer command
        bytes memory messageWithSignature_ProcessClaim = signMessageForEigenAgentExecution(
            deployerKey,
            address(eigenAgent),
            EthSepolia.ChainId, // destination chainid where EigenAgent lives
            address(rewardsCoordinator),
            encodeProcessClaimMsg(claim, EARNERS[0]),
            execNonce,
            expiry
        );

        rewardsAmount = REWARDS_AMOUNTS1[0];
        rewardsToken = address(tokenL1);

        ///////////////////////////////////////////////
        // L2: Send a rewards processClaim message and fundsTransfer commitment
        ///////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        routerFees = getRouterFeesL2(
            address(receiverContract),
            string(messageWithSignature_ProcessClaim),
            new Client.EVMTokenAmount[](0),
            senderHooks.getGasLimitForFunctionSelector(IRewardsCoordinator.processClaim.selector)
            // gasLimit
        );

        senderContract.sendMessagePayNative{value: routerFees}(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_ProcessClaim),
            new Client.EVMTokenAmount[](0),
            0 // use default gasLimit for this function
        );

        ///////////////////////////////////////////////
        // L1 Receiver processes the rewards processClaim message
        // Then dispatches a FundsTransfer message back to L1
        ///////////////////////////////////////////////
        vm.selectFork(ethForkId);

        uint256 rewardsCoordinatorBalanceBefore = tokenL1.balanceOf(address(rewardsCoordinator));
        vm.assertTrue(memecoin.balanceOf(deployer) == 0);

        /// Expect 3 emitted events:
        /// 1) RewardsClaimed for tokenL1 which will be bridged back to L2
        /// 2) RewardsClaimed for a memecoin which will just be transferred to AgentOwner on L1.
        /// 3) BridgingRewardsToL2 event

        vm.expectEmit(true, true, true, false);
        emit RewardsClaimed(
            tree.root,
            address(eigenAgent), // earner
            address(eigenAgent), // claimer
            address(eigenAgent), // recipient
            tokenL1,
            rewardsAmount
        );

        vm.expectEmit(true, true, true, false);
        emit RewardsClaimed(
            tree.root,
            address(eigenAgent), // earner
            address(eigenAgent), // claimer
            address(eigenAgent), // recipient
            memecoin,
            rewardsAmount
        );

        // only for testing rewards event
        Client.EVMTokenAmount[] memory rewardsEventTokenAmounts = new Client.EVMTokenAmount[](1);
        rewardsEventTokenAmounts[0] = Client.EVMTokenAmount({
            token: rewardsToken,
            amount: rewardsAmount
        });

        vm.expectEmit(true, true, true, false);
        emit ReceiverCCIP.BridgingRewardsToL2(deployer, rewardsEventTokenAmounts);

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(address(senderContract)),
                data: abi.encode(string(
                    messageWithSignature_ProcessClaim
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0) // should be empty
            })
        );

        // check memecoin rewards were distributed to AgentOwner
        vm.assertTrue(memecoin.balanceOf(deployer) > 0);

		vm.assertEq(
            tokenL1.balanceOf(address(rewardsCoordinator)),
            rewardsCoordinatorBalanceBefore - rewardsAmount
        );

        ////////////////////////////////////////uuu///////
        // L2 Sender receives tokens from L1 and transfers to agentOwner
        ///////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        Client.EVMTokenAmount[] memory destTokenAmountsL2 = new Client.EVMTokenAmount[](1);
        destTokenAmountsL2[0] = Client.EVMTokenAmount({
            token: BaseSepolia.BridgeToken, // CCIP-BnM token address on L2
            amount: rewardsAmount
        });

        vm.expectEmit(true, true, false, false);
        emit SendingFundsToAgentOwner(deployer, rewardsAmount);
        senderContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(address(receiverContract)),
                data: abi.encode(string(
                    encodeTransferToAgentOwnerMsg(deployer)
                )),
                destTokenAmounts: destTokenAmountsL2
            })
        );
    }
}
