import { Address, Hex, keccak256, encodeAbiParameters, encodePacked } from 'viem';
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

  // For a single claim, tokenTreeProofs can be empty as it's just the root
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
