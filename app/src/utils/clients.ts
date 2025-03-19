import { createPublicClient, http, PublicClient, Chain } from 'viem';
import { sepolia, baseSepolia } from 'viem/chains';

// RPC URLs
const SEPOLIA_RPC_URL = 'https://sepolia.gateway.tenderly.co';
const BASE_SEPOLIA_RPC_URL = 'https://base-sepolia.gateway.tenderly.co';

/**
 * Creates a public client for Ethereum Sepolia (L1)
 * @returns Public client for Ethereum Sepolia
 */
export function createL1Client(): PublicClient {
  return createPublicClient({
    chain: sepolia,
    transport: http(SEPOLIA_RPC_URL)
  });
}

/**
 * Creates a public client for Base Sepolia (L2)
 * @returns Public client for Base Sepolia
 */
export function createL2Client(): PublicClient {
  // Use type assertion to ensure the chain type is compatible
  return createPublicClient({
    chain: baseSepolia as Chain,
    transport: http(BASE_SEPOLIA_RPC_URL)
  });
}

// Cached client instances for reuse
let l1ClientInstance: PublicClient | null = null;
let l2ClientInstance: PublicClient | null = null;

/**
 * Gets a cached L1 public client or creates a new one if none exists
 * @returns Cached or new L1 client
 */
export function getL1Client(): PublicClient {
  if (!l1ClientInstance) {
    l1ClientInstance = createL1Client();
  }
  return l1ClientInstance;
}

/**
 * Gets a cached L2 public client or creates a new one if none exists
 * @returns Cached or new L2 client
 */
export function getL2Client(): PublicClient {
  if (!l2ClientInstance) {
    l2ClientInstance = createL2Client();
  }
  return l2ClientInstance;
}