import { Address, Hex, keccak256, encodeAbiParameters } from 'viem';
import {
  RewardsMerkleClaim,
  TokenTreeMerkleLeaf,
  EarnerTreeMerkleLeaf
} from '../abis/generated/RewardsCoordinatorTypes';
import { RewardsCoordinatorABI } from '../abis';

// Reward amount constant - can be adjusted as needed
export const REWARDS_AMOUNT = 1000000000000000000n; // 1 ETH in wei

/**
 * Calculate the token leaf hash equivalent to the Solidity implementation
 *
 * @param tokenLeaf The token leaf with token address and cumulative earnings
 * @returns The keccak256 hash of the encoded leaf
 */
export function calculateTokenLeafHash(tokenLeaf: TokenTreeMerkleLeaf): Hex {
  // This replicates the Solidity function that encodes and hashes the token leaf
  return keccak256(
    encodeAbiParameters(
      [
        { name: 'token', type: 'address' },
        { name: 'cumulativeEarnings', type: 'uint256' }
      ],
      [tokenLeaf.token, tokenLeaf.cumulativeEarnings]
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
  earnerIndex: number = 0,
  tokenAddress?: Address
): RewardsMerkleClaim {
  // Use default token address if not provided
  const token = tokenAddress || '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE' as Address;

  // Create token leaf
  const tokenLeaf: TokenTreeMerkleLeaf = {
    token: token,
    cumulativeEarnings: amount
  };

  // Calculate token leaf hash (would normally call the contract)
  const tokenLeafHash = calculateTokenLeafHash(tokenLeaf);

  // Create earner leaf
  const earnerLeaf: EarnerTreeMerkleLeaf = {
    earner: earner,
    earnerTokenRoot: tokenLeafHash
  };

  // For a single claim, tokenIndices is just [0]
  const tokenIndices: number[] = [0];

  // For a single claim, tokenTreeProofs can be empty as it's just the root
  const tokenTreeProofs: Hex[] = ['0x'];

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
 * @param eigenAgentAddress The address of the EigenAgent
 * @param rewardsCoordinatorAddress The address of the RewardsCoordinator contract
 * @param claim The claim to process
 * @returns True if the simulation was successful, false otherwise
 */
export async function simulateRewardClaim(
  l1Client: any,
  eigenAgentAddress: Address,
  rewardsCoordinatorAddress: Address,
  claim: RewardsMerkleClaim,
  recipient: Address
): Promise<boolean> {
  try {
    // Encode the call to processClaim
    const calldata = encodeAbiParameters(
      [
        {
          name: 'selector',
          type: 'bytes4'
        },
        {
          name: 'claim',
          type: 'tuple',
          components: [
            { name: 'rootIndex', type: 'uint32' },
            { name: 'earnerIndex', type: 'uint32' },
            { name: 'earnerTreeProof', type: 'bytes' },
            {
              name: 'earnerLeaf',
              type: 'tuple',
              components: [
                { name: 'earner', type: 'address' },
                { name: 'earnerTokenRoot', type: 'bytes32' }
              ]
            },
            { name: 'tokenIndices', type: 'uint32[]' },
            { name: 'tokenTreeProofs', type: 'bytes[]' },
            {
              name: 'tokenLeaves',
              type: 'tuple[]',
              components: [
                { name: 'token', type: 'address' },
                { name: 'cumulativeEarnings', type: 'uint256' }
              ]
            }
          ]
        },
        {
          name: 'recipient',
          type: 'address'
        }
      ],
      [
        '0x3ccc861d', // processClaim selector
        claim,
        recipient
      ]
    );

    // Simulate the call through the EigenAgent
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
      ]
    });

    console.log('Simulation result:', result);
    return true;
  } catch (error) {
    console.error('Simulation failed:', error);
    return false;
  }
}