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
  eigenAgentAddress: Address
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
    console.log("rewards merkle tree: ", tree);

    // hardcoded the earnerIndex to be 1 for this EigenAgent. Based on 9_submitRewards.s.sol script
    const earnerIndex = 1;
    const proof = generateClaimProof(tree, earnerIndex);

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
  // const formattedProof = Array.isArray(proofData.proof) && proofData.proof.length > 0
  //   ? proofData.proof[0] as unknown as Hex
  //   : "0x0" as Hex;

  const formattedProof = proofData.proof;
  console.log("Formatted proof: ", formattedProof);

  return createClaim(
    currentDistRootIndex,
    eigenAgentAddress,
    proofData.amount,
    formattedProof,
    proofData.earnerIndex
  );
}
