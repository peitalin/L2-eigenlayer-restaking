import { PublicClient, Abi, WalletClient, TransactionReceipt, keccak256, toHex } from 'viem';
import { SENDER_CCIP_ADDRESS } from '../addresses';
import { SenderCCIPABI } from '../abis';
import { CCIPTransaction } from '../contexts/TransactionHistoryContext';

// MessageSent event signature
const MESSAGE_SENT_EVENT = {
  name: 'MessageSent',
  inputs: [
    { indexed: true, name: 'messageId', type: 'bytes32' },
    { indexed: true, name: 'destinationChainSelector', type: 'uint64' },
    { name: 'receiver', type: 'address' },
    { name: 'tokenAmounts', type: 'tuple[]' },
    { name: 'feeToken', type: 'address' },
    { name: 'fees', type: 'uint256' }
  ]
} as const;

// Calculate the event signature hash
const MESSAGE_SENT_SIGNATURE = `${MESSAGE_SENT_EVENT.name}(${MESSAGE_SENT_EVENT.inputs.map(input =>
  input.type === 'tuple[]' ? 'tuple[]' : input.type).join(',')})`;
const MESSAGE_SENT_TOPIC = keccak256(toHex(MESSAGE_SENT_SIGNATURE));

// This is the known topic hash for MessageSent event used as a fallback
const KNOWN_MESSAGE_SENT_TOPIC = '0x8c5261668696ce22758910d05bab8f186d6eb247ceac2af2e82c7dc17669b036';

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

    // Step 1: Try with the calculated topic
    let messageSentEvents = receipt.logs.filter(log => {
      const isSenderAddress = log.address.toLowerCase() === SENDER_CCIP_ADDRESS.toLowerCase();
      const hasCalculatedTopic = log.topics[0] === MESSAGE_SENT_TOPIC;
      if (isSenderAddress) console.log('Found sender address in log, topic match:', hasCalculatedTopic);
      return isSenderAddress && hasCalculatedTopic;
    });

    // Step 2: If no events found, try with the known hardcoded topic
    if (messageSentEvents.length === 0) {
      console.log('No events found with calculated topic, trying hardcoded topic');
      messageSentEvents = receipt.logs.filter(log => {
        const isSenderAddress = log.address.toLowerCase() === SENDER_CCIP_ADDRESS.toLowerCase();
        const hasKnownTopic = log.topics[0] === KNOWN_MESSAGE_SENT_TOPIC;
        if (isSenderAddress) console.log('Found sender address in log, known topic match:', hasKnownTopic);
        return isSenderAddress && hasKnownTopic;
      });
    }

    // Step 3: Last resort - check any events from the sender address with enough topics
    if (messageSentEvents.length === 0) {
      console.log('No events found with known topics, checking all events from sender');
      messageSentEvents = receipt.logs.filter(log => {
        const isSenderAddress = log.address.toLowerCase() === SENDER_CCIP_ADDRESS.toLowerCase();
        const hasEnoughTopics = log.topics.length > 1;
        if (isSenderAddress) console.log('Found sender address in log, has enough topics:', hasEnoughTopics);
        return isSenderAddress && hasEnoughTopics;
      });
    }

    // Step 4: No events found from the sender
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