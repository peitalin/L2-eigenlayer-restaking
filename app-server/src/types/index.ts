
export interface ErrorResponse {
  message?: string;
  details?: string;
  code?: string;
  shortMessage?: string;
}

// Define the Operator type
export interface Operator {
  name: string;
  address: string;
  magicStaked: string;
  ethStaked: string;
  stakers: number;
  fee: string;
  isActive: boolean;
}

// Define types for CCIP message data
export interface CCIPMessageData {
  messageId: string;
  state: number;
  status: string; // SUCCESS, INFLIGHT, FAILED, etc.
  sourceChainId: string;
  destChainId: string;
  receiptTransactionHash?: string;
  destTxHash?: string; // Destination transaction hash
  data?: string;
  sender?: string;
  receiver?: string;
  blessBlockNumber?: boolean;
  execNonce?: number; // EigenAgent execution nonce
}
// See:
// https://ccip.chain.link/api/h/atlas/message/0x405715b39feb8ce9771064ea9f9ad42b837c1e73dd811ab87f1e86ffa3d93f8c
