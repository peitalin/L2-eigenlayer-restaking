import { createPublicClient, http, PublicClient } from 'viem';
import { sepolia, baseSepolia } from 'viem/chains';
import { ETH_CHAINID, L2_CHAINID } from './constants';
import type { Transaction } from '../db';

// Create public clients to interact with different chains
export const publicClientL1 = createPublicClient({
  chain: sepolia,
  transport: http(process.env.SEPOLIA_RPC_URL || 'https://ethereum-sepolia.publicnode.com')
});

// Create a second client for Base Sepolia (L2)
export const publicClientL2 = createPublicClient({
  chain: baseSepolia,
  transport: http(process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org')
});

// Helper function to determine which client to use based on transaction properties
export function determineClientFromTransaction(transaction: Transaction): PublicClient {
  // If the transaction has a sourceChainId, use it to determine the client
  if (transaction.sourceChainId) {
    const sourceChain = transaction.sourceChainId;
    if (sourceChain === L2_CHAINID) {
      return publicClientL2 as unknown as PublicClient;
    } else if (sourceChain === ETH_CHAINID) {
      return publicClientL1 as unknown as PublicClient;
    }
  }

  // Otherwise, determine based on transaction type
  switch (transaction.txType) {
    case 'bridgingWithdrawalToL2':
    case 'bridgingRewardsToL2':
      return publicClientL1 as unknown as PublicClient; // Use L1 client for bridging operations
    default:
      return publicClientL2 as unknown as PublicClient; // Default to L2 client
  }
}