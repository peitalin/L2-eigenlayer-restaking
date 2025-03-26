import { EthSepolia , TreasureTopaz} from "./addresses";
import { BaseSepolia } from "./addresses";
import { ChainlinkConfig } from "./addresses";

// Define server base URL
export const SERVER_BASE_URL = import.meta.env.VITE_SERVER_BASE_URL;
console.log('SERVER_BASE_URL:', SERVER_BASE_URL);

// RPC URLs
export const SEPOLIA_RPC_URL = 'https://sepolia.gateway.tenderly.co';
export const BASE_SEPOLIA_RPC_URL = 'https://base-sepolia.gateway.tenderly.co';

// App configuration
export const APP_CONFIG = {
  // App settings
  APP_NAME: 'EigenLayer Restaking',
  DEFAULT_EXPIRY_MINUTES: 45,

  // UI settings
  TOAST_TIMEOUT: 4000,

  // Feature flags
  ENABLE_REWARDS_FEATURE: true,
  ENABLE_DELEGATION_FEATURE: true,

  // Default gas limits
  GAS_LIMITS: {
    DEPOSIT: 500000n,
    WITHDRAW_QUEUE: 700000n,
    WITHDRAW_COMPLETE: 800000n,
    DELEGATE: 400000n,
    UNDELEGATE: 300000n,
    CLAIM_REWARDS: 590000n,
  }
};

export const EXPLORER_URLS = {
  L2: 'https://sepolia.basescan.org',
  L1: 'https://sepolia.etherscan.io',
  ccip: 'https://ccip.chain.link'
}

// Network mapping for easy lookups
export const NETWORKS: Record<number, ChainlinkConfig> = {
  [EthSepolia.chainId]: EthSepolia,
  [BaseSepolia.chainId]: BaseSepolia,
  [TreasureTopaz.chainId]: TreasureTopaz,
};

// Default network configs
export const DEFAULT_L1_NETWORK = EthSepolia;
export const DEFAULT_L2_NETWORK = BaseSepolia;