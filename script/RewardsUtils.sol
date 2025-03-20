// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRewardsCoordinator} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {IRewardsCoordinatorTypes} from "@eigenlayer-contracts/interfaces/IRewardsCoordinator.sol";
import {Merkle} from "@eigenlayer-contracts/libraries/Merkle.sol";

struct TestRewardsTree {
    bytes32 root;
    bytes32 h1;
    bytes32 h2;
    bytes32 h3;
    bytes32 h4;
    bytes32 h5;
    bytes32 h6;
}

contract RewardsUtils {

    /**
     * @param earners Users eligible to claim rewards for this epoch
     * @param token1 reward token, must be on L1
     * @param rewardAmounts1 amounts of token1 for users to claim (for this epoch)
     * @return tree is the Rewards merkle tree (for 4 users)
    */
    function createEarnerTreeOneToken(
        IRewardsCoordinator rewardsCoordinator,
        address[4] memory earners,
        address token1, // L1 coin
        uint256[4] memory rewardAmounts1
    ) public pure returns (TestRewardsTree memory) {

        bytes32[] memory leaves = new bytes32[](4);
        // create earner leaf hashes for each user
        for (uint32 i = 0; i < earners.length; ++i) {

            bytes32 earnerTokenRoot = rewardsCoordinator.calculateTokenLeafHash(
                IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
                    token: IERC20(token1),
                    cumulativeEarnings: rewardAmounts1[i]
                })
            );

            leaves[i] = rewardsCoordinator.calculateEarnerLeafHash(
                IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf({
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

    /**
     * @param earners Users eligible to claim rewards for this epoch
     * @param token1 reward token, must be on L1
     * @param token2 reward token, must be on L1
     * @param rewardAmounts1 amounts of token1 for users to claim (for this epoch)
     * @param rewardAmounts2 amounts of token2 for users to claim (for this epoch)
     * @return tree is the Rewards merkle tree (for 4 users)
    */
    function createEarnerTreeTwoTokens(
        IRewardsCoordinator rewardsCoordinator,
        address[4] memory earners,
        address token1, // L1 coin
        address token2, // L1 memecoin
        uint256[4] memory rewardAmounts1,
        uint256[4] memory rewardAmounts2
    ) public pure returns (TestRewardsTree memory) {

        bytes32[] memory leaves = new bytes32[](4);
        // create earner leaf hashes for each user
        for (uint32 i = 0; i < earners.length; ++i) {

            bytes32 earnerTokenRoot = keccak256(abi.encode(
                rewardsCoordinator.calculateTokenLeafHash(
                    IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
                        token: IERC20(token1),
                        cumulativeEarnings: rewardAmounts1[i]
                    })
                ),
                rewardsCoordinator.calculateTokenLeafHash(
                    IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
                        token: IERC20(token2),
                        cumulativeEarnings: rewardAmounts2[i]
                    })
                )
            ));

            leaves[i] = rewardsCoordinator.calculateEarnerLeafHash(
                IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf({
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

    function generateClaimProof(
        TestRewardsTree memory tree,
        uint32 earnerIndex
    ) public pure returns (bytes memory) {
        //       root
        //      /     \
        //    h1       h2
        //  /   \     /  \
        // h4    h3  h6   h5
        require(earnerIndex < 4, "This rewards tree only supports 4 users");
        bytes memory proof;

        if (earnerIndex == 0) {
            // EarnerIndex is element[0] on the bottom of the tree (left-to-right) => h4
            // h4's proof claim is: [h3, h2] as hash(hash(h4, h3), h2) = root
            proof = bytes.concat(tree.h3, tree.h2);
            // check proof:
            bytes32 generatedRoot = Merkle.processInclusionProofKeccak(proof, tree.h4, earnerIndex);
            require(tree.root == generatedRoot, "invalid generated root");
        }

        if (earnerIndex == 1) {
            // EarnerIndex is element[1] on the bottom of the tree (left-to-right) => h3
            // h3's proof claim is: [h4, h2] as hash(hash(h4, h3), h2) = root
            proof = bytes.concat(tree.h4, tree.h2);
            // check proof:
            bytes32 generatedRoot = Merkle.processInclusionProofKeccak(proof, tree.h3, earnerIndex);
            require(tree.root == generatedRoot, "invalid generated root");
        }

        if (earnerIndex == 2) {
            // EarnerIndex is element[2] on the bottom of the tree (left-to-right) => h6
            // h6's proof claim is: [h5, h1] as hash(hash(h6, h5), h1) = root
            proof = bytes.concat(tree.h5, tree.h1);
            // check proof:
            bytes32 generatedRoot = Merkle.processInclusionProofKeccak(proof, tree.h6, earnerIndex);
            require(tree.root == generatedRoot, "invalid generated root");
        }

        if (earnerIndex == 3) {
            // EarnerIndex is element[3] on the bottom of the tree (left-to-right) => h5
            // h5's proof claim is: [h6, h1] as hash(hash(h6, h5), h1) = root
            proof = bytes.concat(tree.h6, tree.h1);
            // check proof:
            bytes32 generatedRoot = Merkle.processInclusionProofKeccak(proof, tree.h5, earnerIndex);
            require(tree.root == generatedRoot, "invalid generated root");
        }

        return proof;
    }

    function createClaimOneToken(
        IRewardsCoordinator rewardsCoordinator,
        uint32 distRootIndex,
        address earner,
        uint32 earnerIndex,
        bytes memory proof,
        address token1, // tokenL1
        uint256 amount1
    ) public pure returns (IRewardsCoordinator.RewardsMerkleClaim memory claim) {

		IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves;
        tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](1);
		tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
            token: IERC20(token1),
            cumulativeEarnings: amount1
        });

        bytes32 leaf1 = rewardsCoordinator.calculateTokenLeafHash(tokenLeaves[0]);

		IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf memory earnerLeaf;
        earnerLeaf = IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf({
			earner: earner,
			earnerTokenRoot: leaf1
		});

        uint32[] memory tokenIndices = new uint32[](1);
        tokenIndices[0] = 0;

		// Only 1 claims entries in the TokenClaim tree, so proof is empty (just the root)
        bytes[] memory tokenTreeProofs = new bytes[](1);
        tokenTreeProofs[0] = hex"";

		return IRewardsCoordinatorTypes.RewardsMerkleClaim({
			rootIndex: distRootIndex,
			earnerIndex: earnerIndex,
			earnerTreeProof: proof,
			earnerLeaf: earnerLeaf,
			tokenIndices: tokenIndices,
			tokenTreeProofs: tokenTreeProofs,
			tokenLeaves: tokenLeaves
		});
	}

    function createClaimTwoTokens(
        IRewardsCoordinator rewardsCoordinator,
        uint32 distRootIndex,
        address earner,
        uint32 earnerIndex,
        bytes memory proof,
        address token1, // tokenL1
        address token2, // memecoin
        uint256 amount1,
        uint256 amount2
    ) public pure returns (IRewardsCoordinator.RewardsMerkleClaim memory claim) {

		IRewardsCoordinator.TokenTreeMerkleLeaf[] memory tokenLeaves;
		IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf memory earnerLeaf;
        uint32[] memory tokenIndices = new uint32[](2);
        bytes[] memory tokenTreeProofs = new bytes[](2);

        {
            tokenLeaves = new IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[](2);
            tokenLeaves[0] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
                token: IERC20(token1),
                cumulativeEarnings: amount1
            });
            tokenLeaves[1] = IRewardsCoordinatorTypes.TokenTreeMerkleLeaf({
                token: IERC20(token2),
                cumulativeEarnings: amount2
            });

            bytes32 leaf1 = rewardsCoordinator.calculateTokenLeafHash(tokenLeaves[0]);
            bytes32 leaf2 = rewardsCoordinator.calculateTokenLeafHash(tokenLeaves[1]);
            earnerLeaf = IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf({
                earner: earner,
                earnerTokenRoot: keccak256(abi.encode(
                    leaf1,
                    leaf2
                ))
            });

            tokenIndices[0] = 0;
            tokenIndices[1] = 1;

            // Only 2 claims entries in the TokenClaim tree, so proof is just the other leaf (h(l1, l2) = root):
            tokenTreeProofs[0] = abi.encode(leaf2); // proof for leaf1 is the other leaf2
            tokenTreeProofs[1] = abi.encode(leaf1); // proof for leaf2 is the other leaf1
        }

		return IRewardsCoordinatorTypes.RewardsMerkleClaim({
			rootIndex: distRootIndex,
			earnerIndex: earnerIndex,
			earnerTreeProof: proof,
			earnerLeaf: earnerLeaf,
			tokenIndices: tokenIndices,
			tokenTreeProofs: tokenTreeProofs,
			tokenLeaves: tokenLeaves
		});
	}
}