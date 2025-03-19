import { PublicClient, Abi, WalletClient, TransactionReceipt, keccak256, toHex, toBytes } from 'viem';
import { SENDER_CCIP_ADDRESS } from '../addresses';
import { CCIPTransaction } from '../contexts/TransactionHistoryContext';


// Define server base URL
const SERVER_BASE_URL = 'http://localhost:3001';

const MESSAGE_SENT_SIGNATURE = keccak256(toBytes('MessageSent(bytes32 indexed, uint64 indexed, address, (address, uint256)[], address, uint256)'));
// cast sig-event 'MessageSent(bytes32 indexed, uint64 indexed, address, (address, uint256)[], address, uint256)'
// is: 0xf41bc76bbe18ec95334bdb88f45c769b987464044ead28e11193a766ae8225cb

/**
 * Processes a transaction receipt to extract CCIP event data
 * @param receipt The transaction receipt to process
 * @param senderAddress The address that sent the transaction (user's address)
 * @param targetContract The target contract that will receive the message on the destination chain
 * @param txType The type of transaction ('deposit', 'withdrawal', etc.)
 * @returns A CCIP transaction object with event data
 */
export async function processCCIPTransaction(
  receipt: TransactionReceipt,
  senderAddress: string,
  targetContract: string,
  txType: 'deposit' | 'withdrawal' | 'completeWithdrawal' | 'other',
  user: string
): Promise<CCIPTransaction | null> {
  try {
    console.log('Processing CCIP transaction receipt:', receipt.transactionHash);
    console.log('Log count in receipt:', receipt.logs.length);

    // Step 1: Extract MessageSent events from the receipt
    let messageSentEvents = receipt.logs.filter(log => {
      const isSenderAddress = log.address.toLowerCase() === SENDER_CCIP_ADDRESS.toLowerCase();
      const hasCalculatedTopic = log.topics[0] === MESSAGE_SENT_SIGNATURE;
      if (isSenderAddress) console.log('Found sender address in log, topic match:', hasCalculatedTopic);
      return isSenderAddress && hasCalculatedTopic;
    });

    // Step 2: No events found from the sender
    if (messageSentEvents.length === 0) {
      console.warn('No MessageSent events found from CCIP sender');

      // Log all event topics to help debug
      console.log('All event topics in receipt:');
      receipt.logs.forEach((log, index) => {
        console.log(`Log ${index}:`, {
          address: log.address,
          topics: log.topics
        });
      });

      // Return a transaction without messageId to still track the transaction
      return {
        txHash: receipt.transactionHash,
        messageId: '', // Empty messageId when not found
        timestamp: Math.floor(Date.now() / 1000),
        type: txType,
        status: receipt.status === 'success' ? 'confirmed' : 'failed',
        from: senderAddress,
        to: targetContract,
        user: user,
      };
    }

    // Get the first MessageSent event (most transactions only have one)
    const event = messageSentEvents[0];
    console.log('Found MessageSent event:', {
      address: event.address,
      topics: event.topics,
      data: event.data
    });

    // Make sure we have a second topic for the messageId
    if (!event.topics[1]) {
      console.warn('MessageSent event does not contain a messageId topic');
      return {
        txHash: receipt.transactionHash,
        messageId: '', // Empty messageId when not found
        timestamp: Math.floor(Date.now() / 1000),
        type: txType,
        status: receipt.status === 'success' ? 'confirmed' : 'failed',
        from: senderAddress,
        to: targetContract,
        user: user,
      };
    }

    // Extract messageId from the first topic
    const messageId = event.topics[1] as string;
    console.log('Extracted messageId:', messageId);

    return {
      txHash: receipt.transactionHash,
      messageId: messageId,
      timestamp: Math.floor(Date.now() / 1000), // Current Unix timestamp
      type: txType,
      status: receipt.status === 'success' ? 'confirmed' : 'failed',
      from: senderAddress,
      to: targetContract,
      user: user,
    };
  } catch (error) {
    console.error('Error processing CCIP transaction:', error);
    // Return a transaction without messageId instead of null to still track the transaction
    return {
      txHash: receipt.transactionHash,
      messageId: '', // Empty messageId on error
      timestamp: Math.floor(Date.now() / 1000),
      type: txType,
      status: receipt.status === 'success' ? 'confirmed' : 'failed',
      from: senderAddress,
      to: targetContract,
      user: user,
    };
  }
}

/**
 * Watches for a specific transaction to be mined and processes any CCIP events
 * @param publicClient The public client to use for watching
 * @param txHash The transaction hash to watch
 * @param senderAddress The address that sent the transaction
 * @param targetContract The target contract that will receive the message
 * @param txType The type of transaction
 * @param user The user's address
 * @param onComplete Callback when processing is complete
 */
export async function watchCCIPTransaction(
  publicClient: PublicClient,
  txHash: string,
  senderAddress: string,
  targetContract: string,
  txType: 'deposit' | 'withdrawal' | 'completeWithdrawal' | 'other',
  user: string,
  onComplete: (transaction: CCIPTransaction | null) => void
): Promise<void> {
  try {
    console.log('Watching for CCIP transaction:', txHash);

    // Watch for transaction receipt
    const receipt = await publicClient.waitForTransactionReceipt({
      hash: txHash as `0x${string}`,
    });

    console.log('Transaction receipt received:', receipt.transactionHash);

    // Process the transaction to extract CCIP data
    const ccipTransaction = await processCCIPTransaction(
      receipt,
      senderAddress,
      targetContract,
      txType,
      user
    );

    // Call the completion callback with the result
    if (ccipTransaction) {
      console.log('CCIP transaction processed successfully:', ccipTransaction);
      onComplete(ccipTransaction);
    } else {
      console.warn('Failed to process CCIP transaction, returning null');
      onComplete(null);
    }
  } catch (error) {
    console.error('Error watching CCIP transaction:', error);
    onComplete(null);
  }
}

/**
 * Creates a CCIP explorer URL for a given messageId
 * @param messageId The CCIP message ID
 * @returns A URL to the CCIP explorer
 */
export function getCCIPExplorerUrl(messageId: string): string {
  if (!messageId || messageId === '') {
    return 'https://ccip.chain.link';
  }
  return `https://ccip.chain.link/#/side-drawer/msg/${messageId}`;
}

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