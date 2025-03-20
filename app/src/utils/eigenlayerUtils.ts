import { Address, getContract, encodeAbiParameters, keccak256 } from 'viem';
import { agentFactoryAbi, eigenAgentAbi } from '../abis';
import bridgeContractsL1Config from '../addresses/ethsepolia/bridgeContractsL1.config.json';
import { getL1Client } from './clients';
import { ZeroAddress } from './encoders';
import { DELEGATION_MANAGER_ADDRESS } from '../addresses';

// Get agent factory address from the correct config file
const AGENT_FACTORY_ADDRESS = bridgeContractsL1Config.contracts.agentFactory as Address;

// Log the address we're using for debugging
// console.log('Using AgentFactory address:', AGENT_FACTORY_ADDRESS);

// Get the L1 client from the clients utility
const publicClient = getL1Client();

/**
 * Converts an Ethereum block number to a timestamp
 * @param blockNumber The block number to convert
 * @returns The timestamp in seconds since epoch
 */
export async function blockNumberToTimestamp(blockNumber: bigint): Promise<number> {
  try {
    // Ensure the blockNumber is a valid BigInt
    const safeBlockNumber = BigInt(blockNumber.toString());

    // Fetch the block details
    const block = await publicClient.getBlock({
      blockNumber: safeBlockNumber
    });

    // Return the timestamp (which is in seconds since epoch)
    return Number(block.timestamp);
  } catch (error) {
    console.error('Error fetching block timestamp:', error);
    throw new Error(`Failed to get timestamp for block ${blockNumber}`);
  }
}

/**
 * Formats a block timestamp as a human-readable date string
 * @param timestamp Timestamp in seconds
 * @returns Formatted date string
 */
export function formatBlockTimestamp(timestamp: number): string {
  return new Date(timestamp * 1000).toLocaleString();
}

/**
 * Gets the minimum withdrawal delay blocks from the DelegationManager contract
 * @returns The minimum withdrawal delay in blocks
 */
export async function getMinWithdrawalDelayBlocks(): Promise<bigint> {
  try {
    const result = await publicClient.readContract({
      address: DELEGATION_MANAGER_ADDRESS,
      abi: [
        {
          name: 'minWithdrawalDelayBlocks',
          type: 'function',
          inputs: [],
          outputs: [{ type: 'uint32', name: '' }],
          stateMutability: 'view'
        }
      ],
      functionName: 'minWithdrawalDelayBlocks'
    });

    return BigInt(result as number);
  } catch (error) {
    console.error('Error getting minimum withdrawal delay blocks:', error);
    throw new Error('Failed to get minimum withdrawal delay blocks');
  }
}

/**
 * Calculates the withdrawal root hash for a withdrawal
 * TypeScript equivalent of Solidity: keccak256(abi.encode(withdrawalStruct))
 *
 * @param staker The address of the staker
 * @param delegatedTo The address staker is delegated to
 * @param withdrawer The address that will receive the withdrawal
 * @param nonce The withdrawal nonce
 * @param startBlock The block when the withdrawal was initiated
 * @param strategies Array of strategy addresses
 * @param shares Array of share amounts
 * @returns The keccak256 hash of the encoded withdrawal struct
 */
export function calculateWithdrawalRoot(
  staker: Address,
  delegatedTo: Address,
  withdrawer: Address,
  nonce: bigint,
  startBlock: bigint,
  strategies: Address[],
  scaledShares: bigint[]
): string {
  // In Solidity, the struct is defined like this in IDelegationManager.sol:
  // struct Withdrawal {
  //     address staker;
  //     address delegatedTo;
  //     address withdrawer;
  //     uint256 nonce;
  //     uint32 startBlock;
  //     IStrategy[] strategies;
  //     uint256[] scaledShares;
  // }

  // This matches exactly how the struct is encoded in Solidity's abi.encode
  const encodedData = encodeAbiParameters(
    [
      {
        type: 'tuple',
        components: [
          { name: 'staker', type: 'address' },
          { name: 'delegatedTo', type: 'address' },
          { name: 'withdrawer', type: 'address' },
          { name: 'nonce', type: 'uint256' },
          { name: 'startBlock', type: 'uint32' },
          { name: 'strategies', type: 'address[]' },
          { name: 'scaledShares', type: 'uint256[]' }
        ]
      }
    ],
    [
      {
        staker,
        delegatedTo,
        withdrawer,
        nonce,
        startBlock: Number(startBlock), // Convert to uint32
        strategies,
        scaledShares
      }
    ]
  );

  // Calculate the keccak256 hash
  return keccak256(encodedData);
}

/**
 * Gets the EigenAgent address and execution nonce for a user
 * Equivalent to getEigenAgentAndExecNonce in BaseScript.sol
 */
export async function getEigenAgentAndExecNonce(userAddress: Address): Promise<{
  eigenAgentAddress: Address;
  execNonce: bigint;
} | null> {
  try {
    // Get the EigenAgent address for the user using readContract
    const eigenAgentAddress = await publicClient.readContract({
      address: AGENT_FACTORY_ADDRESS,
      abi: agentFactoryAbi,
      functionName: 'getEigenAgent',
      args: [userAddress]
    }) as Address;

    // If user has no EigenAgent, return null
    if (eigenAgentAddress === ZeroAddress) {
      return null;
    }

    // Get the current execution nonce
    const execNonce = await publicClient.readContract({
      address: eigenAgentAddress,
      abi: eigenAgentAbi,
      functionName: 'execNonce',
      args: []
    }) as bigint;

    return {
      eigenAgentAddress,
      execNonce,
    };
  } catch (error) {
    console.error('Error in getEigenAgentAndExecNonce:', error);
    // Return null instead of a partial object
    return null;
  }
}

/**
 * Simple function to check if the contract exists and is accessible
 */
export async function checkAgentFactoryContract(): Promise<boolean> {
  try {
    // Try to get the contract code at the address
    const code = await publicClient.getBytecode({
      address: AGENT_FACTORY_ADDRESS,
    });

    // If there's no code, it's not a contract
    if (!code || code === '0x') {
      console.error('No contract found at address:', AGENT_FACTORY_ADDRESS);
      return false;
    }

    return true;
  } catch (error) {
    console.error('Error checking AgentFactory contract:', error);
    return false;
  }
}

/**
 * Predicts the EigenAgent address for a user before it's minted
 * This is equivalent to agentFactory.predictEigenAgentAddress(staker, 0) in Solidity
 */
export async function predictEigenAgentAddress(userAddress: Address): Promise<Address> {
  try {
    // Call the predictEigenAgentAddress function on the AgentFactory contract
    const predictedAddress = await publicClient.readContract({
      address: AGENT_FACTORY_ADDRESS,
      abi: agentFactoryAbi,
      functionName: 'predictEigenAgentAddress',
      args: [userAddress, 0n] // Use 0 as salt/nonce for first-time users
    }) as Address;

    console.log('Predicted EigenAgent address:', predictedAddress);
    return predictedAddress;
  } catch (error) {
    console.error('Error predicting EigenAgent address:', error);
    throw new Error('Failed to predict EigenAgent address');
  }
}