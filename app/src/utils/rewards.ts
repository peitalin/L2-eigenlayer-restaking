import { Address, Hex, keccak256, encodeAbiParameters, encodePacked, concat } from 'viem';
import {
  RewardsMerkleClaim,
  TokenTreeMerkleLeaf,
  EarnerTreeMerkleLeaf
} from '../abis/RewardsCoordinatorTypes';
import {encodeProcessClaimMsg} from "./encoders";
import {EthSepolia} from "../addresses";

export const REWARDS_AMOUNT = 100000000000000000n;
// 0.1 ETH in wei, defined in 9_submitRewards.s.sol
// Hardcoded here until we switch to Eigenlayer's RewardsCoordinator

/**
 * Calculate the token leaf hash equivalent to the Solidity implementation
 *
 * @param tokenLeaf The token leaf with token address and cumulative earnings
 * @returns The keccak256 hash of the encoded leaf
 */
export function calculateTokenLeafHash(tokenLeaf: TokenTreeMerkleLeaf): Hex {
  // This replicates the Solidity function that encodes and hashes the token leaf
  // function calculateTokenLeafHash(
  //     TokenTreeMerkleLeaf calldata leaf
  // ) public pure returns (bytes32) {
  //     return keccak256(abi.encodePacked(TOKEN_LEAF_SALT, leaf.token, leaf.cumulativeEarnings));
  // }
  // uint8 internal constant TOKEN_LEAF_SALT = 1;
  const TOKEN_LEAF_SALT = 1;
  return keccak256(
    encodePacked(
      ['uint8', 'address', 'uint256'],
      [TOKEN_LEAF_SALT, tokenLeaf.token, tokenLeaf.cumulativeEarnings]
    )
  );
}

/**
 * Calculate the earner leaf hash equivalent to the Solidity implementation
 *
 * @param earnerLeaf The earner leaf with earner address and earner token root
 * @returns The keccak256 hash of the encoded leaf
 */
export function calculateEarnerLeafHash(earnerLeaf: EarnerTreeMerkleLeaf): Hex {
  // This replicates the Solidity function that encodes and hashes the earner leaf
  // function calculateEarnerLeafHash(
  //     EarnerTreeMerkleLeaf calldata leaf
  // ) public pure returns (bytes32) {
  //     return keccak256(abi.encodePacked(EARNER_LEAF_SALT, leaf.earner, leaf.earnerTokenRoot));
  // }
  // uint8 internal constant EARNER_LEAF_SALT = 0;
  const EARNER_LEAF_SALT = 0;
  return keccak256(
    encodePacked(
      ['uint8', 'address', 'bytes32'],
      [EARNER_LEAF_SALT, earnerLeaf.earner, earnerLeaf.earnerTokenRoot]
    )
  );
}

/**
 * Creates a RewardsMerkleClaim equivalent to the Solidity function:
 *
 * function createClaim(
 *     uint32 rootIndex,
 *     address earner,
 *     uint256 _amount,
 *     bytes memory proof,
 *     uint32 earnerIndex
 * ) public view returns (IRewardsCoordinator.RewardsMerkleClaim memory claim)
 *
 * @param rootIndex The index of the root in the distribution roots array
 * @param earner The address of the earner claiming rewards
 * @param amount The amount of rewards to claim
 * @param proof The Merkle proof for the earner (empty for single claim)
 * @param earnerIndex The index of the earner in the Merkle tree
 * @param tokenAddress The address of the token for the rewards
 * @returns A RewardsMerkleClaim structure ready for submission
 */
export function createClaim(
  rootIndex: number,
  earner: Address,
  amount: bigint,
  proof: Hex = '0x',
  earnerIndex: number = 0
): RewardsMerkleClaim {

  // Create token leaf
  const tokenLeaf: TokenTreeMerkleLeaf = {
    token: EthSepolia.bridgeToken,
    cumulativeEarnings: amount
  };

  // Calculate token leaf hash
  const tokenLeafHash = calculateTokenLeafHash(tokenLeaf);
  console.log("Token leaf hash: ", tokenLeafHash);

  // Create earner leaf
  const earnerLeaf: EarnerTreeMerkleLeaf = {
    earner: earner,
    earnerTokenRoot: tokenLeafHash
  };

  // Calculate earner leaf hash
  const earnerLeafHash = calculateEarnerLeafHash(earnerLeaf);
  console.log("Earner leaf hash: ", earnerLeafHash)

  // For a single token claim, tokenTreeProofs can be empty as it's just the root
  const tokenTreeProofs: Hex[] = ['0x'];

  const tokenIndices: number[] = [0];

  // Return the complete claim structure
  return {
    rootIndex,
    earnerIndex,
    earnerTreeProof: proof,
    earnerLeaf,
    tokenIndices,
    tokenTreeProofs,
    tokenLeaves: [tokenLeaf]
  };
}

/**
 * Simulate a reward claim through the EigenAgent
 *
 * @param l1Client The L1 ethers client to use for the simulation
 * @param walletAddress The address of the connected wallet (owner of the EigenAgent)
 * @param eigenAgentAddress The address of the EigenAgent
 * @param rewardsCoordinatorAddress The address of the RewardsCoordinator contract
 * @param claim The claim to process
 * @param recipient The recipient address for the rewards
 * @returns True if the simulation was successful, false otherwise
 */
export async function simulateRewardClaim(
  l1Client: any,
  walletAddress: Address,
  eigenAgentAddress: Address,
  rewardsCoordinatorAddress: Address,
  claim: RewardsMerkleClaim,
  recipient: Address
): Promise<boolean> {
  try {
    // Encode the call to processClaim
    const calldata = encodeProcessClaimMsg(claim, recipient);
    console.log("Calldata processedClaim: ", calldata);

    // Log the wallet address for debugging
    console.log("Simulating with account:", walletAddress);

    // Simulate the call through the EigenAgent with the provided wallet address
    const result = await l1Client.simulateContract({
      address: eigenAgentAddress,
      abi: [
        {
          name: 'execute',
          type: 'function',
          inputs: [
            { name: 'to', type: 'address' },
            { name: 'value', type: 'uint256' },
            { name: 'data', type: 'bytes' },
            { name: 'operation', type: 'uint8' }
          ],
          outputs: [{ name: '', type: 'bytes' }],
          stateMutability: 'nonpayable'
        }
      ] as const,
      functionName: 'execute',
      args: [
        rewardsCoordinatorAddress,
        0n,
        calldata,
        0
      ],
      account: walletAddress
    });

    console.log('Simulation result:', result);
    return true;
  } catch (error) {
    console.error('Simulation failed:', error);
    return false;
  }
}

// Equivalent structure to TestRewardsTree in Solidity
export interface TestRewardsTree {
  root: Hex;
  h1: Hex;
  h2: Hex;
  h3: Hex;
  h4: Hex;
  h5: Hex;
  h6: Hex;
}

/**
 * Creates a rewards Merkle tree for a single token.
 *
 * Example usage:
 * const tree = createEarnerTreeOneToken(
 *   [
 *     '0x1',
 *     '0x2',
 *     '0x3',
 *     '0x4'
 *   ] as [Address, Address, Address, Address],
 *   EthSepolia.bridgeToken as Address,
 *   [
 *     100000000000000000n,
 *     200000000000000000n,
 *     300000000000000000n,
 *     400000000000000000n
 *   ] as [bigint, bigint, bigint, bigint]
 * );
 *
 * @param rewardsCoordinator - Contract with hash calculation functions
 * @param earners - Array of 4 earner addresses
 * @param token - The reward token address
 * @param rewardAmounts - Array of 4 reward amounts
 * @returns A TestRewardsTree with all the tree nodes
 */
export function createEarnerTreeOneToken(
  earners: [Address, Address, Address, Address],
  token: Address,
  rewardAmounts: [bigint, bigint, bigint, bigint]
): TestRewardsTree {
  // Create leaf hashes for each earner
  const leaves: Hex[] = new Array(4);

  for (let i = 0; i < earners.length; i++) {
    // Calculate token leaf hash
    const tokenLeaf: TokenTreeMerkleLeaf = {
      token: token,
      cumulativeEarnings: rewardAmounts[i]
    };
    const earnerTokenRoot = calculateTokenLeafHash(tokenLeaf);

    // Calculate earner leaf hash
    const earnerLeaf: EarnerTreeMerkleLeaf = {
      earner: earners[i],
      earnerTokenRoot: earnerTokenRoot
    };
    leaves[i] = calculateEarnerLeafHash(earnerLeaf);
  }

  // Assign leaf nodes
  const h4 = leaves[0];
  const h3 = leaves[1];
  const h6 = leaves[2];
  const h5 = leaves[3];

  // Create intermediate nodes
  // Note: Using concat() for bytes.concat in Solidity
  const h1 = keccak256(concat([h4, h3]));
  const h2 = keccak256(concat([h6, h5]));

  // Create root node
  const root = keccak256(concat([h1, h2]));

  // Return the complete tree
  return {
    root,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6
  };
}

/**
 * Generate a Merkle proof for a specific earner in the rewards tree
 *
 * @param tree The rewards Merkle tree
 * @param earnerIndex The index of the earner (0-3)
 * @returns The proof as a hex string
 */
export function generateClaimProof(
  tree: TestRewardsTree,
  earnerIndex: number
): Hex {
  //       root
  //      /     \
  //    h1       h2
  //  /   \     /  \
  // h4    h3  h6   h5

  if (earnerIndex >= 4) {
    throw new Error("This rewards tree only supports 4 users");
  }

  let proof: Hex;

  if (earnerIndex === 0) {
    // EarnerIndex is element[0] on the bottom of the tree (left-to-right) => h4
    // h4's proof claim is: [h3, h2] as hash(hash(h4, h3), h2) = root
    proof = concat([tree.h3, tree.h2]);
  } else if (earnerIndex === 1) {
    // EarnerIndex is element[1] on the bottom of the tree (left-to-right) => h3
    // h3's proof claim is: [h4, h2] as hash(hash(h4, h3), h2) = root
    proof = concat([tree.h4, tree.h2]);
  } else if (earnerIndex === 2) {
    // EarnerIndex is element[2] on the bottom of the tree (left-to-right) => h6
    // h6's proof claim is: [h5, h1] as hash(hash(h6, h5), h1) = root
    proof = concat([tree.h5, tree.h1]);
  } else { // earnerIndex === 3
    // EarnerIndex is element[3] on the bottom of the tree (left-to-right) => h5
    // h5's proof claim is: [h6, h1] as hash(hash(h6, h5), h1) = root
    proof = concat([tree.h6, tree.h1]);
  }

  return proof;
}
