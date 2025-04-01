import { Address, Hex, PublicClient, WalletClient, Chain, TransactionReceipt } from 'viem';

// Chain Network Definitions
export interface NetworkConfig {
  name: string;
  chainId: number;
  rpcUrl: string;
  explorerUrl: string;
  chainSelector?: string;
  bridgeToken?: Address;
}

// Wallet and Client Types
export interface WalletState {
  publicClient: PublicClient | null;
  client: WalletClient | null;
  account: Address | null;
  chain: Chain | null;
  isConnected: boolean;
}

// Transaction Types
export type TransactionType =
  | 'deposit'
  | 'queueWithdrawal'
  | 'completeWithdrawal'
  | 'delegateTo'
  | 'undelegate'
  | 'processClaim'
  | 'other';

export interface TransactionRecord {
  txHash: string;
  messageId: string;
  timestamp: number;
  txType: TransactionType;
  status: 'pending' | 'confirmed' | 'failed';
  from: string;
  to: string;
  user: string;
  isComplete: boolean;
  sourceChainId: string;
  destinationChainId: string;
}

// Token Types
export interface TokenApproval {
  tokenAddress: Address;
  spenderAddress: Address;
  amount: bigint;
}

// EigenLayer Operation Types
export interface EigenLayerOperationConfig {
  // Target for the EigenAgent to call on L1
  targetContractAddr: Address;
  // Amount of tokens to send with the operation
  amount: bigint;
  // Optional token approval details
  tokenApproval?: TokenApproval;
  // Function to call after successful operation
  onSuccess?: (txHash: string, receipt: TransactionReceipt, execNonce: number | null) => void;
  // Function to call after failure
  onError?: (error: Error) => void;
  // Minutes until the signature expires
  expiryMinutes?: number;
  // Optional custom gas limit for L2->L1 transactions
  customGasLimit?: bigint;
}

export interface EigenAgentInfo {
  eigenAgentAddress: Address;
  execNonce: bigint;
}

// Rewards Types
export interface RewardProofData {
  proof: Hex;
  earnerIndex: number;
  amount: bigint;
  token: Address;
}
