// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";
import {ERC20Minter} from "./mocks/ERC20Minter.sol";

import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {Merkle} from "@eigenlayer-contracts/libraries/Merkle.sol";

import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";
import {RouterFees} from "../script/RouterFees.sol";
import {AgentFactory} from "../src/6551/AgentFactory.sol";



contract CCIP_ForkTest_RewardsProcessClaim_Tests is BaseTestEnvironment, RouterFees {

    // SenderHooks.RewardsTransferRootCommitted
    event RewardsTransferRootCommitted(
        bytes32 indexed rewardsTransferRoot,
        address indexed recipient,
        uint256 amount,
        address signer
    );

    event BridgingRewardsToL2(
        bytes32 indexed rewardsTransferRoot,
        address indexed rewardToken,
        uint256 indexed rewardAmount
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

    struct TestRewardsTree {
        bytes32 root;
        bytes32 h1;
        bytes32 h2;
        bytes32 h3;
        bytes32 h4;
        bytes32 h5;
        bytes32 h6;
    }

    TestRewardsTree public tree;
    address[4] earners;
    uint256[4] amounts;
    bytes32[] leaves;
    IERC20 memecoin;

    uint256 execNonce;
    uint256 expiry;
    uint256 routerFees;

    bytes32 rewardsRoot;
    uint256 rewardsAmount;
    address rewardsToken;
    bytes32 rewardsTransferRoot;

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

        // Create a second memecoin ERC20 token for multi-token rewards claims
        memecoin = IERC20(address(new TransparentUpgradeableProxy(
            address(new ERC20Minter()),
            address(new ProxyAdmin()),
            abi.encodeWithSelector(
                ERC20Minter.initialize.selector,
                "token2",
                "TKN2"
            )
        )));
        // Send RewardsCoordinator some tokens for rewards claims
        ERC20Minter(address(memecoin)).mint(address(rewardsCoordinator), 1 ether);
        vm.stopBroadcast();

        secondsInWeek = 604800;
        timeNow = uint32(block.timestamp);
        startOfTheWeek = uint32(block.timestamp) - (uint32(block.timestamp) % secondsInWeek);
        startOfLastWeek = startOfTheWeek - secondsInWeek;
    }

    /*
     *
     *
     *             Setup Eigenlayer State for Rewards Claims
     *
     *
     */

    function _createEarnerTreeMerkleLeaves() internal returns (TestRewardsTree memory) {

        earners = [
            address(eigenAgent),
            bob,
            charlie,
            dani
        ];
        amounts = [0.1 ether, 0.15 ether, 0.2 ether, 0.05 ether];
        leaves = new bytes32[](4);
        // create earner leaf hashes for each user
        for (uint32 i = 0; i < earners.length; ++i) {

            bytes32 earnerTokenRoot = keccak256(abi.encode(
                rewardsCoordinator.calculateTokenLeafHash(
                    IRewardsCoordinator.TokenTreeMerkleLeaf({
                        token: tokenL1,
                        cumulativeEarnings: amounts[i]
                    })
                ),
                rewardsCoordinator.calculateTokenLeafHash(
                    IRewardsCoordinator.TokenTreeMerkleLeaf({
                        token: memecoin,
                        cumulativeEarnings: amounts[i]
                    })
                )
            ));

            leaves[i] = rewardsCoordinator.calculateEarnerLeafHash(
                IRewardsCoordinator.EarnerTreeMerkleLeaf({
                    earner: earners[i],
                    earnerTokenRoot: earnerTokenRoot
                })
            );
        }

        bytes32 h4 = leaves[0];
        bytes32 h3 = leaves[1];
        bytes32 h6 = leaves[2];
        bytes32 h5 = leaves[3];
        // Create the rest of the Earner merkle tree:
        // Hashed leafs are stored back-to-front and alphabetized
        // So you need to: concat(right, left) = concat(leaf6, leaf5)
        // see: https://github.com/OpenZeppelin/merkle-tree/issues/26
        bytes32 h1 = keccak256(bytes.concat(h4, h3));
        bytes32 h2 = keccak256(bytes.concat(h6, h5));
        bytes32 root = keccak256(bytes.concat(h1, h2));
        // Return merkle tree top-down, left-to-right:
        //       root
        //      /     \
        //    h1       h2
        //  /   \     /  \
        // h4    h3  h6   h5
        return TestRewardsTree({
            root: root,
            h1: h1,
            h2: h2,
            h4: h4,
            h3: h3,
            h6: h6,
            h5: h5
        });
    }

	function createClaim(
        address earner,
        uint256 amount,
        bytes memory proof,
        uint32 earnerIndex
    ) public view returns (IRewardsCoordinator.RewardsMerkleClaim memory claim) {

		IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves;
        tokenLeaves = new IRewardsCoordinator.TokenTreeMerkleLeaf[](2);
		tokenLeaves[0] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: tokenL1,
            cumulativeEarnings: amount
        });
		tokenLeaves[1] = IRewardsCoordinator.TokenTreeMerkleLeaf({
            token: memecoin,
            cumulativeEarnings: amount
        });

        bytes32 leaf1 = rewardsCoordinator.calculateTokenLeafHash(tokenLeaves[0]);
        bytes32 leaf2 = rewardsCoordinator.calculateTokenLeafHash(tokenLeaves[1]);

		IRewardsCoordinator.EarnerTreeMerkleLeaf memory earnerLeaf;
        earnerLeaf = IRewardsCoordinator.EarnerTreeMerkleLeaf({
			earner: earner,
			earnerTokenRoot: keccak256(abi.encode(
                leaf1,
                leaf2
            ))
		});

        uint32[] memory tokenIndices = new uint32[](2);
        tokenIndices[0] = 0;
        tokenIndices[1] = 1;

		// Only 2 claims entries in the TokenClaim tree, so proof is just the other leaf (h(l1, l2) = root):
        bytes[] memory tokenTreeProofs = new bytes[](2);
        tokenTreeProofs[0] = abi.encode(leaf2); // proof for leaf1 is the other leaf2
        tokenTreeProofs[1] = abi.encode(leaf1); // proof for leaf2 is the other leaf1

		return IRewardsCoordinator.RewardsMerkleClaim({
			rootIndex: 0,
			earnerIndex: earnerIndex,
			earnerTreeProof: proof,
			earnerLeaf: earnerLeaf,
			tokenIndices: tokenIndices,
			tokenTreeProofs: tokenTreeProofs,
			tokenLeaves: tokenLeaves
		});
	}

    function _setupL1State_RewardsMerkleRoots() internal returns (bytes memory, uint32) {

        // Rewind back to the start of last week:
        vm.warp(startOfLastWeek);
        // NOTE: we need to rewind time otherwise fork tests with CCIP's router do not work.
        // CCIP router's are time-sensitive when fetching fees/prices and fails if warping into future.

        //// Setup reward merkle roots mock users
        tree = _createEarnerTreeMerkleLeaves();
        //       root
        //      /     \
        //    h1       h2
        //  /   \     /  \
        // h4    h3  h6   h5
        // Generate proof for deployer's claim h4:[h3, h2] as hash(hash(h4, h3), h2) = root
        bytes memory proof = bytes.concat(tree.h3, tree.h2);
        uint32 earnerIndex = 0; // 0-th element in the bottom of the tree, left-to-right
        bytes32 generatedRoot = Merkle.processInclusionProofKeccak(proof, tree.h4, earnerIndex);
        vm.assertEq(tree.root, generatedRoot);

        uint32 startTimestamp = startOfLastWeek; // startTimestamp, must be a multiple of 604800 (7 days)
        uint32 duration = 604800; // duration, must be a multiple of 604800

        uint32 rewardsCalculationEndTimestamp = startOfLastWeek + duration;
        vm.warp(startOfLastWeek + duration + 1 hours);
        // wait past rewardsCalculation End Timestamp, then submit root

		/////////////////////////////////////////////////////////////////
		// Submit Rewards Merkle Root
		/////////////////////////////////////////////////////////////////
        vm.prank(deployer);
        vm.expectEmit(true, true, true, false);
        emit IRewardsCoordinator.DistributionRootSubmitted(earnerIndex, tree.root, rewardsCalculationEndTimestamp, 0);
        rewardsCoordinator.submitRoot(tree.root, rewardsCalculationEndTimestamp);

        // There should be 1 DistributionRoot now.
        vm.assertTrue(rewardsCoordinator.getDistributionRootsLength() == 1);

        // Send RewardsCoordinator some tokens for rewards claims
        IERC20_CCIPBnM(address(tokenL1)).drip(address(rewardsCoordinator));

		// Fast forward to present time
        vm.warp(timeNow);

        return (proof, earnerIndex);
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

        (
            bytes memory proof,
            uint32 earnerIndex
        ) = _setupL1State_RewardsMerkleRoots();

        /////////////////////////////////////////////////////////////////
        // Create claim for Alice: earners[0], amounts[0]
		/////////////////////////////////////////////////////////////////
        IRewardsCoordinator.RewardsMerkleClaim memory claim = createClaim(
            earners[0],
            amounts[0],
            proof,
            earnerIndex
        );

		require(rewardsCoordinator.checkClaim(claim), "checkClaim(claim) failed, invalid claim.");

        execNonce = 0;
        expiry = block.timestamp + 1 hours;

        // sign the message for EigenAgent to execute Eigenlayer command
        bytes memory messageWithSignature_PC = signMessageForEigenAgentExecution(
            deployerKey,
            EthSepolia.ChainId, // destination chainid where EigenAgent lives
            address(rewardsCoordinator),
            encodeProcessClaimMsg(claim, earners[0]),
            execNonce,
            expiry
        );

        rewardsRoot = calculateRewardsRoot(claim);
        rewardsAmount = amounts[0];
        rewardsToken = address(tokenL1);
        rewardsTransferRoot = calculateRewardsTransferRoot(
            rewardsRoot,
            rewardsAmount,
            rewardsToken,
            deployer // agentOwner
        );

        ///////////////////////////////////////////////
        // L2: Send a rewards processClaim message and fundsTransfer commitment
        ///////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        routerFees = getRouterFeesL2(
            address(receiverContract),
            string(messageWithSignature_PC),
            address(tokenL2),
            0 ether,
            senderHooks.getGasLimitForFunctionSelector(IRewardsCoordinator.processClaim.selector)
            // gasLimit
        );

        vm.expectEmit(true, true, true, true);
        emit RewardsTransferRootCommitted(
            rewardsTransferRoot,
            address(eigenAgent), // rewards recipient (eigenAgent)
            rewardsAmount,
            deployer // signer (agentOwner)
        );
        senderContract.sendMessagePayNative{value: routerFees}(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_PC),
            address(tokenL2), // destination token
            0, // not sending tokens, just message
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

        vm.expectEmit(true, true, true, false);
        emit BridgingRewardsToL2(rewardsTransferRoot, rewardsToken, rewardsAmount);

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                data: abi.encode(string(
                    messageWithSignature_PC
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );

        // check memecoin rewards were distributed to AgentOwner
        vm.assertTrue(memecoin.balanceOf(deployer) > 0);

		vm.assertEq(
            tokenL1.balanceOf(address(rewardsCoordinator)),
            rewardsCoordinatorBalanceBefore - rewardsAmount
        );

        ///////////////////////////////////////////////
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
                    encodeTransferToAgentOwnerMsg(
                        rewardsTransferRoot
                    )
                )),
                destTokenAmounts: destTokenAmountsL2
            })
        );

        // attempting to re-use a rewardsTransferRoot should fail
        vm.expectRevert("SenderHooks.handleTransferToAgentOwner: TransferRoot already used");
        senderContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(address(receiverContract)),
                data: abi.encode(string(
                    encodeTransferToAgentOwnerMsg(rewardsTransferRoot)
                )),
                destTokenAmounts: destTokenAmountsL2
            })
        );

        uint256 routerFees2 = getRouterFeesL2(
            address(receiverContract),
            string(messageWithSignature_PC),
            address(tokenL2),
            0 ether,
            senderHooks.getGasLimitForFunctionSelector(IRewardsCoordinator.processClaim.selector)
        );
        // attempting to re-commit a spent claim should fail on L2
        vm.expectRevert("SenderHooks._commitRewardsTransferRootInfo: TransferRoot already used");
        senderContract.sendMessagePayNative{value: routerFees2}(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_PC),
            address(tokenL2), // destination token
            0, // not sending tokens, just message
            0 // use default gasLimit for this function
        );

    }

}
