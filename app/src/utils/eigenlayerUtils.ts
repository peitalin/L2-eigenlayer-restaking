import { Address, getContract } from 'viem';
import { agentFactoryAbi, eigenAgentAbi } from '../abis';
import bridgeContractsL1Config from '../addresses/ethsepolia/bridgeContractsL1.config.json';
import { getL1Client } from './clients';

// Get agent factory address from the correct config file
const AGENT_FACTORY_ADDRESS = bridgeContractsL1Config.contracts.agentFactory as Address;

// Log the address we're using for debugging
// console.log('Using AgentFactory address:', AGENT_FACTORY_ADDRESS);

// Get the L1 client from the clients utility
const publicClient = getL1Client();

/**
 * Gets the EigenAgent address and execution nonce for a user
 * Equivalent to getEigenAgentAndExecNonce in BaseScript.sol
 */
export async function getEigenAgentAndExecNonce(userAddress: Address): Promise<{
  eigenAgentAddress: Address | null;
  execNonce: bigint;
}> {
  try {
    // Log parameters for debugging
    // console.log('Checking EigenAgent for address:', userAddress);

    // Create contract instances
    const agentFactory = getContract({
      address: AGENT_FACTORY_ADDRESS,
      abi: agentFactoryAbi,
      publicClient,
    });

    console.log('AgentFactory contract created, attempting to read getEigenAgent...');

    // Get the EigenAgent address for the user
    const eigenAgentAddress = await agentFactory.read.getEigenAgent([userAddress]) as Address;
    // console.log('EigenAgent address:', eigenAgentAddress);

    // If user has no EigenAgent, return null and zero nonce
    if (eigenAgentAddress === '0x0000000000000000000000000000000000000000') {
      return {
        eigenAgentAddress: null,
        execNonce: 0n,
      };
    }

    // Create contract instance for the EigenAgent
    const eigenAgent = getContract({
      address: eigenAgentAddress as Address,
      abi: eigenAgentAbi,
      publicClient,
    });

    // Get the current execution nonce
    const execNonce = await eigenAgent.read.execNonce();

    return {
      eigenAgentAddress: eigenAgentAddress,
      execNonce: execNonce as bigint,
    };
  } catch (error) {
    console.error('Error in getEigenAgentAndExecNonce:', error);
    // return a mock response to allow the UI to function
    return {
      eigenAgentAddress: null,
      execNonce: 0n
    };
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