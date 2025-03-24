import { Address, formatEther, parseEther, Hex } from 'viem';
import { RewardProofData } from '../types';
import { RewardsMerkleClaim } from '../abis/RewardsCoordinatorTypes';
import { createClaim, createEarnerTreeOneToken, generateClaimProof } from './rewards';
import { EthSepolia } from '../addresses';

interface RewardsTreeData {
  earners: Address[];
  token: Address;
  amounts: bigint[];
}

/**
 * In production, this would fetch from an API, but for now we generate locally
 * Creates test/demo earner tree for rewards
 */
export function generateTestEarnerTreeData(eigenAgentAddress: Address): RewardsTreeData {
  // Placeholder test data
  const rewardsAmounts = [
    parseEther('0.1'),
    parseEther('0.2'),
    parseEther('0.3'),
    parseEther('0.4')
  ];

  const earners = [
    eigenAgentAddress,
    "0xAbAc0Ee51946B38a02AD8150fa85E9147bC8851F" as Address,
    "0x1Ceb858C292Db256EF7E378dD85D8b23D7D96E63" as Address,
    "0x0000000000000000000000000000000000000004" as Address
  ];

  // In production, this would be a real token address from the API
  const tokenAddress = EthSepolia.bridgeToken;

  return {
    earners,
    token: tokenAddress,
    amounts: rewardsAmounts
  };
}

/**
 * Get proof data for claiming rewards
 * In production, this would fetch from an API
 * @param eigenAgentAddress The address of the EigenAgent
 * @param currentDistRootIndex The current distribution root index
 * @returns Proof data for claiming rewards
 */
export async function getRewardsProofData(
  eigenAgentAddress: Address,
  currentDistRootIndex: number
): Promise<RewardProofData> {
  try {
    // In production, we would fetch this (earnerIndex and proof) from an API endpoint
    // For now, we generate the proof data locally
    const treeData = generateTestEarnerTreeData(eigenAgentAddress);
    const tree = createEarnerTreeOneToken(
      treeData.earners as [Address, Address, Address, Address],
      treeData.token,
      treeData.amounts as [bigint, bigint, bigint, bigint]
    );

    // First earner is the eigenAgentAddress
    const earnerIndex = 0;
    const proofResult = generateClaimProof(tree, earnerIndex);

    // Convert the proof to the expected format - an array of strings
    // In a real API response, this would already be in the correct format
    const proof: string[] = Array.isArray(proofResult)
      ? proofResult
      : [proofResult as unknown as string];

    return {
      proof,
      earnerIndex,
      amount: treeData.amounts[earnerIndex],
      token: treeData.token
    };
  } catch (error) {
    console.error('Error fetching rewards proof data:', error);
    throw new Error('Failed to get rewards proof data');
  }
}

/**
 * Creates a formatted claim object from proof data
 */
export function createRewardClaim(
  currentDistRootIndex: number,
  eigenAgentAddress: Address,
  proofData: RewardProofData
): RewardsMerkleClaim {
  // Convert the proof array to the expected format for createClaim
  // This is specific to our mock implementation
  const formattedProof = Array.isArray(proofData.proof) && proofData.proof.length > 0
    ? proofData.proof[0] as unknown as Hex
    : "0x0" as Hex;

  return createClaim(
    currentDistRootIndex,
    eigenAgentAddress,
    proofData.amount,
    formattedProof,
    proofData.earnerIndex
  );
}