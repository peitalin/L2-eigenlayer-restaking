import { Address, Hex } from 'viem';

/**
 * TypeScript equivalent for the IRewardsCoordinatorTypes.TokenTreeMerkleLeaf struct
 */
export interface TokenTreeMerkleLeaf {
  token: Address;       // IERC20 token address
  cumulativeEarnings: bigint; // Amount of cumulative earnings
}

/**
 * TypeScript equivalent for the IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf struct
 */
export interface EarnerTreeMerkleLeaf {
  earner: Address;         // Address of the earner
  earnerTokenRoot: Hex;    // Root hash of earner's token claims
}

/**
 * TypeScript equivalent for the IRewardsCoordinatorTypes.RewardsMerkleClaim struct
 */
export interface RewardsMerkleClaim {
  rootIndex: number;               // Root index in distribution roots array
  earnerIndex: number;             // Earner index in the merkle tree
  earnerTreeProof: Hex;            // Merkle proof for earner leaf
  earnerLeaf: EarnerTreeMerkleLeaf; // Earner merkle leaf
  tokenIndices: number[];          // Indices of token leaves to claim
  tokenTreeProofs: Hex[];          // Proofs for each token leaf
  tokenLeaves: TokenTreeMerkleLeaf[]; // Token merkle leaves with earnings
}

/**
 * TypeScript equivalent for the IRewardsCoordinator.DistributionRoot struct
 */
export interface DistributionRoot {
  distRootHash: Hex;     // Root hash of the distribution merkle tree
  claimableEndBlock: bigint; // Block after which claims are no longer valid
  earnerAndTokenRoot: Hex; // Root of the earner and token merkle trees
  totalEarningsDistributed: bigint; // Total amount distributed in this root
  totalEarnerTokenLeaves: number; // Total number of earner token leaves
  tokenCount: number;    // Number of tokens in this distribution
}