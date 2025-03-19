import express from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { config } from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { promises as fsPromises } from 'fs';
import { createPublicClient, http, decodeEventLog, PublicClient, keccak256, toBytes } from 'viem';
import { sepolia } from 'viem/chains';
import { parseAbi } from 'viem/utils';
import * as db from './db.js';

// Chain ID constants
const ETH_CHAINID = "11155111"; // Ethereum Sepolia
const L2_CHAINID = "84532";     // Base Sepolia

/**
 * L2-eigenlayer-restaking Transaction Server
 *
 * This server provides the following functionality:
 * 1. Stores transactions in a SQLite database for querying
 * 2. Tracks cross-chain transaction status using CCIP message IDs
 * 3. Provides endpoints for clients to add and query transactions
 * 4. Automatically updates transaction status in the background
 *
 * Database Schema:
 * - Transactions are stored in SQLite with indexes for fast querying by:
 *   - Transaction hash (txHash)
 *   - CCIP message ID (messageId)
 *   - User address (user)
 *
 * Endpoints:
 * - GET /api/transactions - Get all transactions
 * - GET /api/transactions/user/:address - Get a user's transactions
 * - GET /api/transactions/hash/:txHash - Get a transaction by hash
 * - GET /api/transactions/messageId/:messageId - Get a transaction by message ID
 * - POST /api/transactions/add - Add a new transaction
 * - POST /api/transactions/bridging - Create or update a bridging transaction
 * - POST /api/bridging-transaction-ccip - Create a bridging transaction from CCIP data
 */

// Load environment variables
config();

// Get the directory name
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Initialize express app
const app = express();
const PORT = process.env.SERVER_PORT || 3001;

// Middleware
app.use(cors());
app.use(express.json());

// Data storage path - ensure the data directory exists for SQLite
const dataDir = path.join(__dirname, 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

// Define types for CCIP message data
interface CCIPMessageData {
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
}

// Define the transaction history interface (now we use the one from db.ts)
type CCIPTransaction = db.Transaction;

// Add this constant for the MessageSent event signature
const MESSAGE_SENT_SIGNATURE = keccak256(toBytes('MessageSent(bytes32 indexed, uint64 indexed, address, (address, uint256)[], address, uint256)'));

// Add event signatures for bridging events
const BRIDGING_WITHDRAWAL_TO_L2_SIGNATURE = keccak256(toBytes('BridgingWithdrawalToL2(address,(address,uint256)[])'));
const BRIDGING_REWARDS_TO_L2_SIGNATURE = keccak256(toBytes('BridgingRewardsToL2(address,(address,uint256)[])'));

// Create public clients to interact with different chains
const publicClientL1 = createPublicClient({
  chain: sepolia,
  transport: http(process.env.SEPOLIA_RPC_URL || 'https://ethereum-sepolia.publicnode.com')
});

// Import Base Sepolia chain configuration
import { baseSepolia } from 'viem/chains';

// Create a second client for Base Sepolia (L2)
const publicClientL2 = createPublicClient({
  chain: baseSepolia,
  transport: http(process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org')
});

// Update variable name for consistency
const publicClient = publicClientL1;

// Function to fetch CCIP message data from an external API
async function fetchCCIPMessageData(messageId: string): Promise<CCIPMessageData | null> {
  try {
    const response = await fetch(`https://ccip.chain.link/api/message/${messageId}`);
    if (!response.ok) {
      throw new Error(`Failed to fetch CCIP message data. Status: ${response.status}`);
    }

    const data = await response.json();

    // Map the API response to our simplified CCIPMessageData interface
    return {
      messageId: data.messageId,
      state: data.state,
      status: getStatusFromState(data.state, data), // Convert numeric state to string status
      sourceChainId: data.sourceChainId,
      destChainId: data.destChainId,
      receiptTransactionHash: data.receiptTransactionHash || null,
      destTxHash: data.receiptTransactionHash || null, // Use receiptTransactionHash as destTxHash
      data: data.data,
      sender: data.sender,
      receiver: data.receiver
    };
  } catch (error) {
    console.error(`Error fetching CCIP message data for messageId ${messageId}:`, error);
    return null;
  }
}

// Helper function to convert numeric state to string status
function getStatusFromState(state: number, data: any): string {
  switch (state) {
    case 0:
      return 'INFLIGHT';
    case 1:
      return 'PENDING';
    case 2:
      return 'SUCCESS';
    case 3:
      return 'FAILED';
    default:
      // If we can't determine state, check if there's a receipt
      if (data.receiptTransactionHash) {
        return 'SUCCESS';
      }
      return 'UNKNOWN';
  }
}

/**
 * Extract a CCIP messageId and agentOwner from a transaction receipt
 * @param receiptHash Transaction hash to extract data from
 * @param client Viem public client to use for fetching the receipt
 * @returns Object containing messageId and agentOwner if found
 */
const extractMessageIdFromReceipt = async (
  receiptHash: string,
  client: PublicClient,
  retryCount = 0
): Promise<{ messageId: string | null, agentOwner: string | null }> => {
  if (!receiptHash || !receiptHash.startsWith('0x')) {
    console.error('Invalid receipt hash provided:', receiptHash);
    return { messageId: null, agentOwner: null };
  }

  try {
    console.log(`Getting transaction receipt for: ${receiptHash}`);
    const hash = receiptHash as `0x${string}`;

    try {
      const receipt = await client.getTransactionReceipt({
        hash
      });

      console.log(`Receipt contains ${receipt.logs.length} logs`);

      // Initialize return values
      let foundMessageId: string | null = null;
      let foundAgentOwner: string | null = null;

      // Find logs that contain the events we're interested in
      for (const log of receipt.logs) {
        // Check for MessageSent event
        if (log.topics[0] === MESSAGE_SENT_SIGNATURE) {
          try {
            console.log('Found MessageSent event, decoding...');
            const decodedLog = decodeEventLog({
              abi: parseAbi(['event MessageSent(bytes32 indexed, uint64 indexed, address, (address, uint256)[], address, uint256)']),
              data: log.data,
              topics: log.topics
            });

            if (decodedLog && decodedLog.args) {
              const args = decodedLog.args as any;
              if (args.messageId) {
                foundMessageId = args.messageId.toString();
                console.log(`Extracted messageId: ${foundMessageId}`);
              }
            }
          } catch (decodeError) {
            console.error('Error decoding MessageSent event:', decodeError);
            // Fallback extraction for messageId
            if (log.topics.length > 1) {
              const topic = log.topics[1];
              if (topic) {
                foundMessageId = topic;
                console.log(`Extracted messageId using fallback method: ${foundMessageId}`);
              }
            }
          }
        }

        // Check for BridgingWithdrawalToL2 event
        else if (log.topics[0] === BRIDGING_WITHDRAWAL_TO_L2_SIGNATURE) {
          try {
            console.log('Found BridgingWithdrawalToL2 event, decoding...');
            const decodedLog = decodeEventLog({
              abi: parseAbi(['event BridgingWithdrawalToL2(address indexed agentOwner, (address, uint256)[] withdrawalTokenAmounts)']),
              data: log.data,
              topics: log.topics
            });

            if (decodedLog && decodedLog.args) {
              const args = decodedLog.args as any;
              if (args.agentOwner) {
                foundAgentOwner = args.agentOwner.toLowerCase();
                console.log(`Extracted agentOwner from BridgingWithdrawalToL2: ${foundAgentOwner}`);
              }
            }
          } catch (decodeError) {
            console.error('Error decoding BridgingWithdrawalToL2 event:', decodeError);
            // Fallback extraction for agentOwner
            if (log.topics.length > 1) {
              const topic = log.topics[1];
              if (topic) {
                const address = `0x${topic.slice(26).toLowerCase()}`;
                // Validate that we have a proper address
                if (address.length === 42) {
                  foundAgentOwner = address;
                  console.log(`Extracted agentOwner using fallback method: ${foundAgentOwner}`);
                }
              }
            }
          }
        }

        // Check for BridgingRewardsToL2 event
        else if (log.topics[0] === BRIDGING_REWARDS_TO_L2_SIGNATURE) {
          try {
            console.log('Found BridgingRewardsToL2 event, decoding...');
            const decodedLog = decodeEventLog({
              abi: parseAbi(['event BridgingRewardsToL2(address indexed agentOwner, (address, uint256)[] rewardsTokenAmounts)']),
              data: log.data,
              topics: log.topics
            });

            if (decodedLog && decodedLog.args) {
              const args = decodedLog.args as any;
              if (args.agentOwner) {
                foundAgentOwner = args.agentOwner.toLowerCase();
                console.log(`Extracted agentOwner from BridgingRewardsToL2: ${foundAgentOwner}`);
              }
            }
          } catch (decodeError) {
            console.error('Error decoding BridgingRewardsToL2 event:', decodeError);
            // Fallback extraction for agentOwner
            if (log.topics.length > 1) {
              const topic = log.topics[1];
              if (topic) {
                const address = `0x${topic.slice(26).toLowerCase()}`;
                // Validate that we have a proper address
                if (address.length === 42) {
                  foundAgentOwner = address;
                  console.log(`Extracted agentOwner using fallback method: ${foundAgentOwner}`);
                }
              }
            }
          }
        }
      }

      return { messageId: foundMessageId, agentOwner: foundAgentOwner };
    } catch (error) {
      // Check if this is a TransactionReceiptNotFoundError (transaction not mined yet)
      if (error.shortMessage && error.shortMessage.includes('could not be found') && retryCount < 3) {
        // Transaction not mined yet, retry with exponential backoff if within retry limit
        const delayMs = Math.pow(2, retryCount) * 1000; // Exponential backoff: 1s, 2s, 4s
        console.log(`Transaction ${receiptHash} not mined yet. Retrying in ${delayMs/1000} seconds... (attempt ${retryCount + 1}/3)`);

        // Wait and retry
        await new Promise(resolve => setTimeout(resolve, delayMs));
        return extractMessageIdFromReceipt(receiptHash, client, retryCount + 1);
      }

      console.error(`Error processing transaction receipt for ${receiptHash}:`, error);
      return { messageId: null, agentOwner: null };
    }
  } catch (outerError) {
    console.error(`Unexpected error processing transaction receipt for ${receiptHash}:`, outerError);
    return { messageId: null, agentOwner: null };
  }
};

// API Routes

// Fetch CCIP message data
app.get('/api/ccip/message/:messageId', async (req, res) => {
  const { messageId } = req.params;

  if (!messageId) {
    return res.status(400).json({ error: 'No messageId provided' });
  }

  try {
    const data = await fetchCCIPMessageData(messageId);

    if (!data) {
      return res.status(404).json({
        error: 'Failed to fetch CCIP message data'
      });
    }

    return res.json(data);
  } catch (error) {
    console.error('Error in API route for fetching CCIP message data:', error);
    return res.status(500).json({ error: 'Failed to fetch CCIP message data' });
  }
});

// GET all transactions
app.get('/api/transactions', (req, res) => {
  try {
    const transactions = db.getAllTransactions();
    res.json(transactions);
  } catch (error) {
    console.error('Error reading transaction history:', error);
    res.status(500).json({ error: 'Failed to read transaction history' });
  }
});

// GET transactions by user address
app.get('/api/transactions/user/:address', (req, res) => {
  try {
    const { address } = req.params;
    const transactions = db.getTransactionsByUser(address);
    res.json(transactions);
  } catch (error) {
    console.error('Error fetching user transactions:', error);
    res.status(500).json({ error: 'Failed to fetch user transactions' });
  }
});

// GET transaction by hash
app.get('/api/transactions/hash/:txHash', (req, res) => {
  try {
    const { txHash } = req.params;
    const transaction = db.getTransactionByHash(txHash);

    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    res.json(transaction);
  } catch (error) {
    console.error('Error fetching transaction by hash:', error);
    res.status(500).json({ error: 'Failed to fetch transaction' });
  }
});

// GET transaction by messageId
app.get('/api/transactions/messageId/:messageId', (req, res) => {
  try {
    const { messageId } = req.params;
    const transaction = db.getTransactionByMessageId(messageId);

    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    res.json(transaction);
  } catch (error) {
    console.error('Error fetching transaction by messageId:', error);
    res.status(500).json({ error: 'Failed to fetch transaction' });
  }
});

// POST a new transaction (client-facing endpoint)
app.post('/api/transactions/add', async (req, res) => {
  try {
    const newTransaction: CCIPTransaction = req.body;

    // Validate transaction type before proceeding
    const validTypes = ['deposit', 'withdrawal', 'completeWithdrawal', 'processClaim', 'bridgingWithdrawalToL2', 'bridgingRewardsToL2', 'other'];
    if (!validTypes.includes(newTransaction.type)) {
      console.error(`Invalid transaction type: ${newTransaction.type}. Valid types are: ${validTypes.join(', ')}`);
      return res.status(400).json({
        error: `Invalid transaction type: ${newTransaction.type}. Valid types are: ${validTypes.join(', ')}`
      });
    }

    // Ensure required fields have values
    if (!newTransaction.sourceChainId) {
      console.log(`No sourceChainId provided for transaction ${newTransaction.txHash}, setting default based on type`);
      // Set default source chain ID based on transaction type
      if (
        newTransaction.type === 'bridgingWithdrawalToL2' ||
        newTransaction.type === 'bridgingRewardsToL2'
      ) {
        newTransaction.sourceChainId = ETH_CHAINID; // Sepolia for L1->L2 bridging
      } else {
        newTransaction.sourceChainId = L2_CHAINID; // Default to Base Sepolia
      }
    }

    if (!newTransaction.destinationChainId) {
      console.log(`No destinationChainId provided for transaction ${newTransaction.txHash}, setting default based on type`);
      // Set default destination chain ID based on transaction type
      newTransaction.destinationChainId =
        newTransaction.sourceChainId === L2_CHAINID
          ? ETH_CHAINID
          : L2_CHAINID;
    }

    // Ensure messageId has a value
    if (!newTransaction.messageId) {
      newTransaction.messageId = newTransaction.txHash;
    }

    // Continue with extracting messageId if needed
    if (!newTransaction.messageId && newTransaction.txHash) {
      try {
        console.log(`Transaction ${newTransaction.txHash} doesn't have a messageId. Attempting to extract...`);

        // Determine which client to use based on transaction type or chainId
        const client = determineClientFromTransaction(newTransaction);

        // Extract messageId from the transaction receipt
        const { messageId, agentOwner } = await extractMessageIdFromReceipt(newTransaction.txHash, client);

        if (messageId) {
          console.log(`Successfully extracted messageId ${messageId} from transaction ${newTransaction.txHash}`);
          newTransaction.messageId = messageId;

          // If we found an agent owner and the transaction doesn't have a user field
          if (agentOwner && (!newTransaction.user || newTransaction.user === '0x0000000000000000000000000000000000000000')) {
            newTransaction.user = agentOwner;
          }
        } else {
          // If no messageId found, use txHash as the messageId
          console.log(`No messageId found for transaction ${newTransaction.txHash}, using txHash as messageId`);
          newTransaction.messageId = newTransaction.txHash;
        }
      } catch (extractError) {
        console.error(`Error extracting messageId from transaction ${newTransaction.txHash}:`, extractError);
        // Use txHash as fallback for messageId
        newTransaction.messageId = newTransaction.txHash;
      }
    }

    // Add the transaction to the database
    const savedTransaction = db.addTransaction(newTransaction);

    // If this is a CCIP transaction and we have a messageId, start watching it for updates
    if (newTransaction.messageId && newTransaction.messageId !== newTransaction.txHash) {
      // Queue an immediate check of this transaction's status
      setTimeout(async () => {
        try {
          await updateTransactionStatus(newTransaction.messageId as string);
        } catch (updateError) {
          console.error(`Error updating transaction status for ${newTransaction.messageId}:`, updateError);
        }
      }, 2000);
    }

    res.json({ success: true, transaction: savedTransaction });
  } catch (error) {
    console.error('Error adding transaction:', error);
    // Provide more specific error message for constraint violations
    if (error.code === 'SQLITE_CONSTRAINT_CHECK') {
      return res.status(400).json({
        error: 'Invalid transaction data. Check that the transaction type and status are valid values.',
        details: error.message
      });
    }
    res.status(500).json({ error: 'Failed to add transaction', details: error.message });
  }
});

// Helper function to determine which client to use based on transaction properties
function determineClientFromTransaction(transaction: CCIPTransaction): PublicClient {
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
  switch (transaction.type) {
    case 'bridgingWithdrawalToL2':
    case 'bridgingRewardsToL2':
      return publicClientL1 as unknown as PublicClient; // Use L1 client for bridging operations
    default:
      return publicClientL2 as unknown as PublicClient; // Default to L2 client
  }
}

// Function to update a transaction's status by checking its CCIP message
async function updateTransactionStatus(messageId: string): Promise<void> {
  try {
    // Get the transaction by messageId
    const transaction = db.getTransactionByMessageId(messageId);
    if (!transaction) {
      console.log(`No transaction found with messageId ${messageId}`);
      return;
    }

    // Skip if transaction is already complete
    if (transaction.isComplete) {
      console.log(`Transaction ${transaction.txHash} is already complete`);
      return;
    }

    // Fetch the CCIP message data
    const messageData = await fetchCCIPMessageData(messageId);
    if (!messageData) {
      console.log(`No CCIP message data found for messageId ${messageId}`);
      return;
    }

    // Update transaction based on message status
    let updates: Partial<CCIPTransaction> = {};

    if (messageData.status === 'SUCCESS') {
      updates = {
        status: 'confirmed',
        isComplete: true,
        receiptTransactionHash: messageData.receiptTransactionHash || transaction.receiptTransactionHash
      };
      console.log(`Updating transaction ${transaction.txHash} to confirmed status`);
    } else if (messageData.status === 'FAILED') {
      updates = {
        status: 'failed',
        isComplete: true
      };
      console.log(`Updating transaction ${transaction.txHash} to failed status`);
    } else {
      // Transaction is still in progress, no updates needed
      console.log(`Transaction ${transaction.txHash} is still in progress (${messageData.status})`);
      return;
    }

    // Apply the updates
    db.updateTransactionByMessageId(messageId, updates);
  } catch (error) {
    console.error(`Error updating transaction status for messageId ${messageId}:`, error);
    throw error;
  }
}

// PUT update a transaction (server-side only - not exposed to frontend)
app.put('/api/transactions/:txHash', (req, res) => {
  try {
    const { txHash } = req.params;
    const updates = req.body;

    // Update the transaction in the database
    const updatedTransaction = db.updateTransaction(txHash, updates);

    if (!updatedTransaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    res.json({ success: true, transaction: updatedTransaction });
  } catch (error) {
    console.error('Error updating transaction:', error);
    res.status(500).json({ error: 'Failed to update transaction' });
  }
});

// PUT update a transaction by messageId (server-side only - not exposed to frontend)
app.put('/api/transactions/messageId/:messageId', (req, res) => {
  try {
    const { messageId } = req.params;
    const updates = req.body;

    // Update the transaction in the database
    const updatedTransaction = db.updateTransactionByMessageId(messageId, updates);

    if (!updatedTransaction) {
      return res.status(404).json({ error: 'Transaction not found for messageId' });
    }

    res.json({ success: true, transaction: updatedTransaction });
  } catch (error) {
    console.error('Error updating transaction by messageId:', error);
    res.status(500).json({ error: 'Failed to update transaction' });
  }
});

// GET /api/reset - clear all transactions (dev only)
app.get("/api/reset", async (req, res) => {
  try {
    await fsPromises.mkdir(dataDir, { recursive: true });
    db.clearTransactions();
    res.status(200).send("Transaction history cleared");
  } catch (error) {
    console.error("Error clearing transaction history:", error);
    res.status(500).send("Failed to clear transaction history");
  }
});

// POST /api/loadTransactionHistory - save transaction history (dev/demo only)
app.post("/api/loadTransactionHistory", async (req, res) => {
  try {
    const transactions = req.body;
    await fsPromises.mkdir(dataDir, { recursive: true });

    db.clearTransactions();
    db.addTransactions(transactions);

    res.status(200).send("Transaction history saved successfully");
  } catch (error) {
    console.error("Error saving transaction history:", error);
    res.status(500).send("Failed to save transaction history");
  }
});

// Add new endpoint to check CCIP transaction completion status
app.post('/api/check-withdrawal-completion', async (req, res) => {
  const { messageId, originalTxHash } = req.body;

  if (!messageId) {
    return res.status(400).json({ error: 'No messageId provided' });
  }

  if (!originalTxHash) {
    return res.status(400).json({ error: 'No originalTxHash provided' });
  }

  try {
    // Step 1: Fetch CCIP message data
    console.log(`Checking completion status for messageId: ${messageId}`);
    const messageData = await fetchCCIPMessageData(messageId);

    if (!messageData) {
      return res.status(404).json({
        error: `Failed to fetch CCIP data for messageId: ${messageId}`
      });
    }

    // Step 2: Check if the transaction has completed (has a receipt transaction hash)
    if (!messageData.receiptTransactionHash) {
      return res.json({
        isComplete: false,
        message: 'Transaction has not been received on the destination chain yet'
      });
    }

    console.log(`Transaction completed with receipt hash: ${messageData.receiptTransactionHash}`);

    // Step 3: Choose the right client based on chainId
    // If chainId is specified, use it to determine which client to use
    let clientToUse: PublicClient = publicClientL1; // Default to L1 client

    if (messageData.destChainId) {
      // Determine which client to use based on chainId
      if (messageData.destChainId === L2_CHAINID) {
        clientToUse = publicClientL2 as PublicClient;
      } else if (messageData.destChainId === ETH_CHAINID) {
        clientToUse = publicClientL1;
      } else {
        console.log(`Unknown chainId ${messageData.destChainId}, defaulting to L1 client`);
      }
    } else {
      console.log('No chainId provided, defaulting to L1 client');
    }

    // Step 4: Get the receipt transaction to check for MessageSent events
    let newMessageId: string | null = null;
    let agentOwner: string | null = null;
    try {
      // Try to extract the messageId and agentOwner from the receipt using the appropriate client
      const { messageId: extractedMessageId, agentOwner: extractedAgentOwner } = await extractMessageIdFromReceipt(
        messageData.receiptTransactionHash as string,
        clientToUse
      );

      if (extractedMessageId) {
        newMessageId = extractedMessageId;
        console.log(`Extracted messageId: ${newMessageId}`);
      }

      if (extractedAgentOwner) {
        agentOwner = extractedAgentOwner;
        console.log(`Extracted agentOwner: ${agentOwner}`);
      }
    } catch (extractError) {
      console.error('Error extracting messageId and agentOwner from receipt:', extractError);
      // Continue with the process even if extraction fails
    }

    // Step 5: Update the original transaction and create bridging transaction if needed

    // 1. First update the original completeWithdrawal transaction
    try {
      // Update the transaction status to confirmed and add the receipt hash
      const updatedOriginalTx = {
        status: 'confirmed' as 'pending' | 'confirmed' | 'failed',
        receiptTransactionHash: messageData.receiptTransactionHash
      };

      // Find and update the original transaction
      const transactions: CCIPTransaction[] = db.getAllTransactions();
      const existingTxIndex = transactions.findIndex(tx => tx.txHash === originalTxHash);

      if (existingTxIndex !== -1) {
        db.updateTransaction(originalTxHash, updatedOriginalTx);
      }

      // 2. If we found a new messageId, add a new transaction for the bridging
      // This is for bridgingWithdrawalToL2 transactions and bridgingRewardsToL2 txs
      let bridgingTransaction: CCIPTransaction | null = null;
      if (newMessageId) {
        console.log(`Creating bridging transaction with messageId: ${newMessageId}`);

        bridgingTransaction = {
          txHash: messageData.receiptTransactionHash as string,
          messageId: newMessageId,
          timestamp: Math.floor(Date.now() / 1000),
          type: 'bridgingWithdrawalToL2',
          status: 'pending',
          from: messageData.sender || '0x0000000000000000000000000000000000000000',
          to: messageData.receiver || '0x0000000000000000000000000000000000000000',
          receiptTransactionHash: messageData.receiptTransactionHash,
          isComplete: messageData.receiptTransactionHash ? true : false,
          sourceChainId: messageData.sourceChainId,
          destinationChainId: messageData.destChainId,
          user: agentOwner || '0x0000000000000000000000000000000000000000',
        };

        // Add the new transaction to history
        db.addTransaction(bridgingTransaction);
      }

      // 3. Return the result
      return res.json({
        isComplete: true,
        message: 'Withdrawal has completed',
        updatedOriginalTx: existingTxIndex !== -1 ? transactions[existingTxIndex] : null,
        bridgingTransaction,
        destChainId: messageData.destChainId
      });
    } catch (updateError) {
      console.error('Error updating transaction history:', updateError);
      return res.status(500).json({
        error: 'Failed to update transaction history',
        isComplete: true,
        message: 'Withdrawal has completed, but failed to update transaction history',
        destChainId: messageData.destChainId
      });
    }
  } catch (error) {
    console.error('Error checking withdrawal completion:', error);
    return res.status(500).json({
      error: 'Failed to check withdrawal completion status',
      details: error.message
    });
  }
});

// Add a new endpoint to create or update bridging transactions
app.post('/api/transactions/bridging', async (req, res) => {
  const { messageId, originalTxHash } = req.body;

  if (!messageId) {
    return res.status(400).json({ error: 'No messageId provided' });
  }

  try {
    // Get CCIP message data
    const messageData = await fetchCCIPMessageData(messageId);

    if (!messageData) {
      return res.status(404).json({
        error: `Failed to fetch CCIP data for messageId: ${messageId}`
      });
    }

    // Use messageId as transaction hash if none is available
    const txHash = messageId;

    // Create bridging transaction
    const bridgingTransaction: db.Transaction = {
      txHash: txHash,
      messageId: messageId,
      timestamp: Math.floor(Date.now() / 1000),
      type: 'bridgingWithdrawalToL2',
      status: 'pending',
      from: messageData.sender || '0x0000000000000000000000000000000000000000',
      to: messageData.receiver || '0x0000000000000000000000000000000000000000',
      receiptTransactionHash: messageData.receiptTransactionHash || null,
      isComplete: messageData.receiptTransactionHash ? true : false,
      sourceChainId: messageData.sourceChainId || ETH_CHAINID,
      destinationChainId: messageData.destChainId || L2_CHAINID,
      user: messageData.sender || '0x0000000000000000000000000000000000000000',
    };

    // Check if transaction already exists
    const existingTxIndex = db.getAllTransactions().findIndex(tx => tx.txHash === txHash);

    if (existingTxIndex !== -1) {
      // Update existing transaction
      db.updateTransaction(txHash, bridgingTransaction);
      console.log(`Updated existing bridging transaction: ${txHash}`);
    } else {
      // Add new transaction
      db.addTransaction(bridgingTransaction);
      console.log(`Added new bridging transaction: ${txHash}`);
    }

    // If original transaction hash is provided, update it too
    if (originalTxHash) {
      const originalTxIndex = db.getAllTransactions().findIndex(tx => tx.txHash === originalTxHash);
      if (originalTxIndex !== -1) {
        db.updateTransaction(originalTxHash, {
          status: 'confirmed',
          receiptTransactionHash: messageData.receiptTransactionHash as string
        });
        console.log(`Updated original transaction: ${originalTxHash}`);
      }
    }

    return res.json({
      success: true,
      bridgingTransaction,
      originalTxUpdated: originalTxHash ? true : false
    });
  } catch (error) {
    console.error('Error creating bridging transaction:', error);
    return res.status(500).json({
      error: 'Failed to create bridging transaction',
      details: error.message
    });
  }
});

// Helper function to determine transaction type based on chain IDs
function getTransactionTypeFromChainIds(sourceChainId: string | number, destChainId: string | number): 'deposit' | 'withdrawal' | 'completeWithdrawal' | 'bridgingWithdrawalToL2' | 'bridgingRewardsToL2' | 'other' {
  const source = sourceChainId;
  const dest = destChainId;

  // For Sepolia and Base Sepolia chains
  if (source === ETH_CHAINID && dest === L2_CHAINID) {
    return 'bridgingWithdrawalToL2'; // From Sepolia (L1) to Base Sepolia (L2)
  } else if (source === L2_CHAINID && dest === ETH_CHAINID) {
    return 'deposit'; // From Base Sepolia (L2) to Sepolia (L1)
  }

  // Default case when chain IDs don't match known patterns
  return 'other';
}

// POST /api/bridging-transaction-ccip
app.post('/api/bridging-transaction-ccip', async (req, res) => {
  try {
    const { messageId } = req.body;
    const messageData = await fetchCCIPMessageData(messageId);

    if (!messageData) {
      return res.status(404).json({ error: 'CCIP message not found' });
    }

    // Use messageId as the transaction hash
    const txHash = messageId;

    // Create a new transaction for this CCIP message
    const bridgingTransaction: db.Transaction = {
      txHash,
      messageId: messageId,
      timestamp: Date.now(),
      type: getTransactionTypeFromChainIds(messageData.sourceChainId, messageData.destChainId),
      status: 'pending', // Use a valid status from the enum
      from: messageData.sender || '0x0000000000000000000000000000000000000000',
      to: messageData.receiver || '0x0000000000000000000000000000000000000000',
      receiptTransactionHash: null,
      isComplete: false,
      sourceChainId: messageData.sourceChainId,
      destinationChainId: messageData.destChainId,
      user: messageData.sender || '0x0000000000000000000000000000000000000000',
    };

    // Add the transaction
    db.addTransaction(bridgingTransaction);

    // If original transaction hash is provided, update it too
    const originalTxHash = req.body.originalTxHash;
    if (originalTxHash) {
      const originalTx = db.getTransactionByHash(originalTxHash);
      if (originalTx) {
        db.updateTransaction(originalTxHash, {
          isComplete: true
        });
        console.log(`Updated original transaction: ${originalTxHash}`);
      }
    }

    // Return the newly created transaction
    res.status(201).json({
      transaction: bridgingTransaction,
      originalTxUpdated: originalTxHash ? true : false
    });
  } catch (error) {
    console.error('Error creating bridging transaction:', error);
    res.status(500).json({ error: 'Failed to create bridging transaction' });
  }
});

// Serve static files from the 'dist' directory (for production)
if (process.env.NODE_ENV === 'production') {
  app.use(express.static(path.join(__dirname, 'dist')));

  app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'dist', 'index.html'));
  });
}

// Start the server
const httpServer = createServer(app);

// Function to check and update pending transactions
async function updatePendingTransactions() {
  try {
    const pendingTransactions = db.getPendingTransactions();

    if (pendingTransactions.length === 0) {
      return;
    }

    console.log(`Checking ${pendingTransactions.length} pending transactions...`);

    for (const tx of pendingTransactions) {
      // If the transaction has a messageId that's different from txHash, check its status
      if (tx.messageId && tx.messageId !== tx.txHash) {
        try {
          const messageData = await fetchCCIPMessageData(tx.messageId);

          if (messageData) {
            // Update transaction status based on message data
            if (messageData.status === 'SUCCESS') {
              console.log(`Transaction ${tx.txHash} (messageId: ${tx.messageId}) completed successfully`);
              db.updateTransactionByMessageId(tx.messageId, {
                status: 'confirmed',
                isComplete: true,
                receiptTransactionHash: messageData.destTxHash || tx.receiptTransactionHash
              });
            } else if (messageData.status === 'FAILED') {
              console.log(`Transaction ${tx.txHash} (messageId: ${tx.messageId}) failed`);
              db.updateTransactionByMessageId(tx.messageId, {
                status: 'failed',
                isComplete: true
              });
            } else {
              console.log(`Transaction ${tx.txHash} (messageId: ${tx.messageId}) is still ${messageData.status}`);
              // No update needed for in-progress transactions
            }
          }
        } catch (error) {
          console.error(`Error updating transaction ${tx.txHash} (messageId: ${tx.messageId}):`, error);
        }
      }
      // For transactions where messageId is the same as txHash, try to extract the real messageId
      else if (tx.messageId === tx.txHash) {
        try {
          console.log(`Checking transaction ${tx.txHash} for messageId...`);

          // Determine which client to use
          const client = determineClientFromTransaction(tx);

          // Attempt to extract messageId
          const { messageId, agentOwner } = await extractMessageIdFromReceipt(tx.txHash, client);

          if (messageId && messageId !== tx.messageId) {
            console.log(`Found messageId ${messageId} for transaction ${tx.txHash}`);

            // Update the transaction with the real messageId
            const updates: Partial<CCIPTransaction> = {
              messageId
            };

            // If we found an agent owner and the transaction doesn't have a valid user
            if (agentOwner &&
                (!tx.user || tx.user === '0x0000000000000000000000000000000000000000')) {
              updates.user = agentOwner;
            }

            // Apply the updates
            db.updateTransaction(tx.txHash, updates);

            // Now check the status of this transaction with the new messageId
            await updateTransactionStatus(messageId);
          } else {
            // If we still couldn't extract a messageId, check if the transaction is confirmed on chain
            try {
              const receipt = await client.getTransactionReceipt({
                hash: tx.txHash as `0x${string}`
              });

              // If we got here, the transaction is confirmed on chain
              // Cast the status to number first to avoid type issues
              const status = Number(receipt.status);
              if (status === 1) {
                console.log(`Transaction ${tx.txHash} confirmed on chain, but no messageId found`);
                db.updateTransaction(tx.txHash, {
                  status: 'confirmed',
                  isComplete: true
                });
              } else if (status === 0) {
                console.log(`Transaction ${tx.txHash} reverted on chain`);
                db.updateTransaction(tx.txHash, {
                  status: 'failed',
                  isComplete: true
                });
              }
            } catch (receiptError) {
              // Transaction might still be pending, do nothing
              console.log(`Transaction ${tx.txHash} not yet confirmed on chain`);
            }
          }
        } catch (error) {
          console.error(`Error checking for messageId in transaction ${tx.txHash}:`, error);
        }
      }
    }
  } catch (error) {
    console.error('Error checking pending transactions:', error);
  }
}

// Start the pending transaction checker
let pendingTxIntervalId: NodeJS.Timeout | null = null;

function startPendingTransactionChecker() {
  if (pendingTxIntervalId === null) {
    // Check every 2 minutes
    pendingTxIntervalId = setInterval(updatePendingTransactions, 2 * 60 * 1000);
    console.log('Started pending transaction checker');

    // Also run immediately
    updatePendingTransactions();
  }
}

function stopPendingTransactionChecker() {
  if (pendingTxIntervalId !== null) {
    clearInterval(pendingTxIntervalId);
    pendingTxIntervalId = null;
    console.log('Stopped pending transaction checker');
  }
}

// Start the checker when the server starts
startPendingTransactionChecker();

// Clean shutdown handler
process.on('SIGINT', () => {
  console.log('Shutting down server gracefully...');
  stopPendingTransactionChecker();
  httpServer.close(() => {
    console.log('HTTP server closed');
    process.exit(0);
  });
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received. Shutting down server gracefully...');
  stopPendingTransactionChecker();
  httpServer.close(() => {
    console.log('HTTP server closed');
    process.exit(0);
  });
});

// After initializing the server, fix any transactions with missing fields
httpServer.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);

  // Run an initial update when the server starts
  updatePendingTransactions();
  startPendingTransactionChecker();
});

// Utility function to convert CCIP message state to a human-readable status
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

// Database initialization
try {
  fsPromises.mkdir(dataDir, { recursive: true }).then(() => {
    console.log('Data directory created or confirmed');

    // Check if we need to migrate existing data
    fs.access(path.join(dataDir, 'transactions.json'), fs.constants.F_OK, (err) => {
      if (!err) {
        console.log('Found existing transactions.json file, migrating to SQLite...');
        fs.readFile(path.join(dataDir, 'transactions.json'), 'utf8', (err, data) => {
          if (err) {
            console.error('Error reading transactions file:', err);
          } else {
            try {
              const transactionsData = JSON.parse(data);
              if (Array.isArray(transactionsData) && transactionsData.length > 0) {

                // Validate and clean up transactions before importing
                const validTransactions = transactionsData.filter(tx => {
                  // Ensure each transaction has the required fields
                  if (!tx || typeof tx !== 'object') return false;
                  if (!tx.txHash || typeof tx.txHash !== 'string') return false;

                  // Set reasonable defaults for missing fields
                  tx.messageId = tx.messageId || tx.txHash;
                  tx.timestamp = tx.timestamp || Math.floor(Date.now() / 1000);
                  tx.type = tx.type || 'other';
                  tx.status = tx.status || 'pending';
                  tx.from = tx.from || '0x0000000000000000000000000000000000000000';
                  tx.to = tx.to || '0x0000000000000000000000000000000000000000';
                  tx.isComplete = !!tx.isComplete;
                  tx.user = tx.user || tx.from || '0x0000000000000000000000000000000000000000';

                  return true;
                });

                console.log(`Found ${transactionsData.length} transactions, ${validTransactions.length} are valid`);

                if (validTransactions.length > 0) {
                  db.addTransactions(validTransactions);
                  console.log(`Migrated ${validTransactions.length} transactions to SQLite database`);

                  // // Create backup of the JSON file
                  // const backupPath = path.join(dataDir, `transactions_backup_${Date.now()}.json`);
                  // fs.copyFile(path.join(dataDir, 'transactions.json'), backupPath, (err) => {
                  //   if (err) {
                  //     console.error('Error creating backup of transactions.json:', err);
                  //   } else {
                  //     console.log(`Created backup of transactions.json at ${backupPath}`);
                  //   }
                  // });
                }
              } else {
                console.log('No transactions to migrate');
              }
            } catch (parseError) {
              console.error('Error parsing transactions file:', parseError);
            }
          }
        });
      } else {
        console.log('No existing transactions.json file found');
      }
    });
  });
} catch (error) {
  console.error('Error initializing database:', error);
}

// GET /api/reset-database - Reset the database (rerun initialization)
app.get("/api/reset-database", async (req, res) => {
  try {
    console.log("Resetting and reinitializing database...");

    // Drop existing table if it exists
    try {
      db.db.prepare("DROP TABLE IF EXISTS transactions").run();
      console.log("Dropped existing transactions table");
    } catch (dropError) {
      console.error("Error dropping table:", dropError);
    }

    // Reinitialize the database
    db.initDatabase();

    res.status(200).send("Database reset and reinitialized successfully");
  } catch (error) {
    console.error("Error resetting database:", error);
    res.status(500).send(`Failed to reset database: ${error.message}`);
  }
});