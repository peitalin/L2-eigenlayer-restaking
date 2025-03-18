import { PublicClient, decodeEventLog } from 'viem';
import { useTransactionHistory, CCIPTransaction } from '../contexts/TransactionHistoryContext';
import { SenderCCIPABI } from '../abis';

// Define server base URL
const SERVER_BASE_URL = 'http://localhost:3001';

// Define the structure of the CCIP message data from the API
export interface CCIPMessageData {
  messageId: string;
  state: number;
  votes: any;
  sourceNetworkName: string;
  destNetworkName: string;
  commitBlockTimestamp: string;
  root: string;
  sendFinalized: string;
  commitStore: string;
  origin: string;
  sequenceNumber: number;
  sender: string;
  receiver: string;
  sourceChainId: string;
  destChainId: string;
  routerAddress: string;
  onrampAddress: string;
  offrampAddress: string;
  destRouterAddress: string;
  sendTransactionHash: string;
  sendTimestamp: string;
  sendBlock: number;
  sendLogIndex: number;
  min: string;
  max: string;
  commitTransactionHash: string;
  commitBlockNumber: number;
  commitLogIndex: number;
  arm: string;
  blessTransactionHash: string | null;
  blessBlockNumber: string | null;
  blessBlockTimestamp: string | null;
  blessLogIndex: string | null;
  receiptTransactionHash: string | null;
  receiptTimestamp: string | null;
  receiptBlock: number | null;
  receiptLogIndex: number | null;
  receiptFinalized: string | null;
  data: string;
  strict: boolean;
  nonce: number;
  feeToken: string;
  gasLimit: string;
  feeTokenAmount: string;
  tokenAmounts: any[];
}

/**
 * Fetches CCIP message data from the server API
 * @param messageId The CCIP message ID to fetch data for
 * @returns A promise that resolves to the CCIP message data
 */
export async function fetchCCIPMessageData(messageId: string): Promise<CCIPMessageData | null> {
  if (!messageId || messageId === '') {
    console.log('No messageId provided to fetchCCIPMessageData');
    return null;
  }

  try {
    console.log(`Fetching CCIP data for messageId: ${messageId}`);

    // Use the app server API instead of calling CCIP API directly
    const response = await fetch(`${SERVER_BASE_URL}/api/ccip/message/${messageId}`);

    if (!response.ok) {
      console.error(`Error fetching CCIP data: ${response.status} ${response.statusText}`);
      return null;
    }

    const data = await response.json();
    console.log('CCIP data received:', data);
    return data as CCIPMessageData;
  } catch (error) {
    console.error('Error fetching CCIP message data:', error);
    return null;
  }
}

/**
 * Checks the status of a CCIP message and updates the transaction history
 * @param messageId The CCIP message ID to check
 * @param updateTransactionByMessageId Function to update the transaction
 */
export async function checkAndUpdateCCIPMessageStatus(
  messageId: string,
  publicClient: PublicClient,
  updateTransactionByMessageId: (messageId: string, updates: Partial<CCIPTransaction>) => Promise<void>
): Promise<void> {
  try {
    // Fetch CCIP message data from the API
    const messageData = await fetchCCIPMessageData(messageId);

    if (!messageData) {
      console.warn(`No data found for messageId: ${messageId}`);
      return;
    }

    // Check if the message has been received on the destination chain
    if (messageData.receiptTransactionHash) {
      console.log(`CCIP message ${messageId} has been received on destination chain.`);

      // Check the receipt transaction for MessageSent events
      try {
        const receipt = await publicClient.getTransactionReceipt({
          hash: messageData.receiptTransactionHash as `0x${string}`
        });

        // Update the transaction status based on the receipt
        await updateTransactionByMessageId(messageId, {
          status: receipt.status === 'success' ? 'confirmed' : 'failed'
        });

      } catch (receiptError) {
        console.error(`Error getting receipt for transaction: ${messageData.receiptTransactionHash}`, receiptError);
      }
    } else {
      console.log(`CCIP message ${messageId} is still in transit (state: ${messageData.state})`);
    }
  } catch (error) {
    console.error(`Error checking CCIP message status for ${messageId}:`, error);
  }
}

/**
 * Extracts the MessageSent event from a transaction receipt
 * @param receipt The transaction receipt
 * @returns The messageId if found, otherwise null
 */
export function extractMessageSentEvent(logs: any[]): string | null {
  try {
    // Look for MessageSent event in the logs
    for (const log of logs) {
      try {
        // Make sure the log has the right shape before trying to decode
        if (!log.topics || log.topics.length < 2) {
          continue;
        }

        // Cast topics to the expected format
        const signatureTopic = log.topics[0] as `0x${string}`;
        const topics: [signature: `0x${string}`, ...args: `0x${string}`[]] = [
          signatureTopic,
          ...(log.topics.slice(1) as `0x${string}`[])
        ];

        const decoded = decodeEventLog({
          abi: SenderCCIPABI,
          data: log.data,
          topics: topics,
        });

        // Check if this is a MessageSent event and extract messageId
        if (decoded.eventName === 'MessageSent' && decoded.args && typeof decoded.args === 'object') {
          // Safely access messageId from args
          const messageId = 'messageId' in decoded.args ? decoded.args.messageId as string : null;
          if (messageId) {
            return messageId;
          }
        }
      } catch (decodeError) {
        // If this log entry isn't a MessageSent event, skip it
        continue;
      }
    }

    return null;
  } catch (error) {
    console.error('Error extracting MessageSent event:', error);
    return null;
  }
}

/**
 * Hook to periodically check for CCIP message updates
 * @param checkIntervalMs How often to check for updates (in milliseconds)
 * @returns Functions to start and stop checking
 */
export function useCCIPMessageStatusChecker(checkIntervalMs: number = 30000) {
  const { transactions, updateTransaction } = useTransactionHistory();

  let intervalId: NodeJS.Timeout | null = null;

  // Function to start checking message statuses
  const startChecking = (publicClient: PublicClient) => {
    if (intervalId) {
      clearInterval(intervalId);
    }

    intervalId = setInterval(() => {
      // Find all transactions with a messageId but not yet confirmed
      const pendingTransactions = transactions.filter(
        tx => tx.messageId && tx.messageId !== '' && tx.status === 'pending'
      );

      // Check each pending transaction
      pendingTransactions.forEach(tx => {
        // Handle async updateTransaction
        checkAndUpdateCCIPMessageStatus(
          tx.messageId,
          publicClient,
          async (messageId, updates) => {
            try {
              await updateTransaction(messageId, updates);
            } catch (error) {
              console.error(`Failed to update transaction ${messageId}:`, error);
            }
          }
        );
      });
    }, checkIntervalMs);

    return () => {
      if (intervalId) {
        clearInterval(intervalId);
        intervalId = null;
      }
    };
  };

  // Function to stop checking
  const stopChecking = () => {
    if (intervalId) {
      clearInterval(intervalId);
      intervalId = null;
    }
  };

  return { startChecking, stopChecking };
}

/**
 * Utility to convert CCIP message state to a human-readable status
 * @param state CCIP message state number
 * @returns Human-readable status
 */
export function getCCIPMessageStatusText(state: number): string {
  switch (state) {
    case 0:
      return 'Pending';
    case 1:
      return 'In Flight';
    case 2:
      return 'Confirmed';
    case 3:
      return 'Failed';
    default:
      return 'Unknown';
  }
}