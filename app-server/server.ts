import express from 'express';
import cors from 'cors';
import https from 'https';
import { config } from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { promises as fsPromises } from 'fs';
import { createPublicClient, http, decodeEventLog, PublicClient, keccak256, toBytes, toHex } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { encodeAbiParameters, concat } from 'viem/utils';
import { sepolia } from 'viem/chains';
import { parseAbi } from 'viem/utils';
import { toEventSignature } from 'viem'
import { signDelegationApproval } from './signDelegationApproval.js';
import * as db from './db.js';
import { Server, Socket } from 'socket.io';
import { router } from './routes.js';
import { SecureVersion } from 'tls';

// Load environment variables
config();

// Validate required environment variables
const requiredEnvVars = ['DELEGATION_MANAGER_ADDRESS'];
const missingEnvVars = requiredEnvVars.filter(varName => !process.env[varName]);
if (missingEnvVars.length > 0) {
  throw new Error(`Missing required environment variables: ${missingEnvVars.join(', ')}`);
}

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
 */

// Get the directory name
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Initialize express app
const app = express();
const PORT = process.env.SERVER_PORT || 3001;

// SSL configuration using Let's Encrypt certificates
const sslOptions = {
  key: fs.readFileSync('/etc/letsencrypt/live/api.l2restaking.info/privkey.pem'),
  cert: fs.readFileSync('/etc/letsencrypt/live/api.l2restaking.info/fullchain.pem'),
  secureProtocol: 'TLS_method',
  minVersion: 'TLSv1.2' as SecureVersion,
  ciphers: [
    'TLS_AES_256_GCM_SHA384',
    'TLS_AES_128_GCM_SHA256',
    'TLS_CHACHA20_POLY1305_SHA256',
    'ECDHE-RSA-AES128-GCM-SHA256',
    'ECDHE-RSA-AES256-GCM-SHA384'
  ].join(':')
};

// Middleware
app.use(cors({
  origin: [
    'https://l2-eigenlayer-restaking-git-frontend-peita-lins-projects.vercel.app',
    /\.vercel\.app$/,
    'http://localhost:5173',
    'http://localhost:3000'
  ],
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));
app.use(express.json());
app.use('/api', router);

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
  blessBlockNumber?: boolean;
  execNonce?: number; // EigenAgent execution nonce
}
// See:
// https://ccip.chain.link/api/h/atlas/message/0x405715b39feb8ce9771064ea9f9ad42b837c1e73dd811ab87f1e86ffa3d93f8c

// Define the transaction history interface (now we use the one from db.ts)
type CCIPTransaction = db.Transaction;

// Add this constant for the MessageSent event signature
const MESSAGE_SENT_SIGNATURE = keccak256(toBytes(toEventSignature('event MessageSent(bytes32 indexed, uint64 indexed, address, (address, uint256)[], address, uint256)')));
// cast sig-event "MessageSent (bytes32 indexed, uint64 indexed, address, (address, uint256)[], address, uint256)"
const KNOWN_MESSAGE_SENT_SIGNATURE = '0xf41bc76bbe18ec95334bdb88f45c769b987464044ead28e11193a766ae8225cb';
if (MESSAGE_SENT_SIGNATURE !== KNOWN_MESSAGE_SENT_SIGNATURE) {
  throw new Error('MESSAGE_SENT_SIGNATURE does not match KNOWN_MESSAGE_SENT_SIGNATURE');
}

// Add event signatures for bridging events
const BRIDGING_WITHDRAWAL_TO_L2_SIGNATURE = keccak256(toBytes(toEventSignature('event BridgingWithdrawalToL2(address,(address,uint256)[])')));
const BRIDGING_REWARDS_TO_L2_SIGNATURE = keccak256(toBytes(toEventSignature('event BridgingRewardsToL2(address,(address,uint256)[])')));

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

// Function to fetch CCIP message data from an external API
async function fetchCCIPMessageData(messageId: string): Promise<CCIPMessageData | null> {
  try {
    const response = await fetch(`https://ccip.chain.link/api/h/atlas/message/${messageId}`);
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
      receiver: data.receiver,
      execNonce: data.execNonce
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
      if (data.blessBlockNumber) {
        return 'BLESSED';
      }
      return 'PENDING';
  }
}

/**
 * Extract a CCIP messageId and agentOwner from a transaction receipt
 * @param txHash Transaction hash to extract data from
 * @param client Viem public client to use for fetching the receipt
 * @returns Object containing messageId and agentOwner if found
 */
const extractMessageIdFromTxHash = async (
  txHash: string,
  client: PublicClient,
  retryCount = 0
): Promise<{ messageId: string | null, agentOwner: string | null }> => {
  if (!txHash || !txHash.startsWith('0x')) {
    console.error('Invalid tx hash provided:', txHash);
    return { messageId: null, agentOwner: null };
  }

  try {
    console.log(`Getting transaction receipt for: ${txHash}`);
    const hash = txHash as `0x${string}`;

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
              foundMessageId = decodedLog.args[0];
              console.log(`Extracted messageId: ${foundMessageId}`);
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
      const errorResponse = error as ErrorResponse;
      // Check if this is a TransactionReceiptNotFoundError (transaction not mined yet)
      if (errorResponse.shortMessage && errorResponse.shortMessage.includes('could not be found') && retryCount < 3) {
        // Transaction not mined yet, retry with exponential backoff if within retry limit
        const delayMs = Math.pow(2, retryCount) * 1000; // Exponential backoff: 1s, 2s, 4s
        console.log(`Transaction ${txHash} not mined yet. Retrying in ${delayMs/1000} seconds... (attempt ${retryCount + 1}/3)`);

        // Wait and retry
        await new Promise(resolve => setTimeout(resolve, delayMs));
        return extractMessageIdFromTxHash(txHash, client, retryCount + 1);
      }

      console.error(`Error processing transaction receipt for ${txHash}:`, error);
      return { messageId: null, agentOwner: null };
    }
  } catch (outerError) {
    console.error(`Unexpected error processing transaction receipt for ${txHash}:`, outerError);
    return { messageId: null, agentOwner: null };
  }
};

// API Routes

// Simple health check endpoint
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', version: '1.0.0' });
});

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

// GET latest execNonce for an EigenAgent
app.get('/api/execnonce/:agentAddress', (req, res) => {
  try {
    const { agentAddress } = req.params;

    if (!agentAddress || !agentAddress.startsWith('0x')) {
      return res.status(400).json({ error: 'Invalid EigenAgent address' });
    }

    const latestNonce = db.getLatestExecNonceForAgent(agentAddress.toLowerCase());

    // If no nonce is found, return 0 as the starting nonce
    const nextNonce = latestNonce !== null ? latestNonce + 1 : 0;

    res.json({
      agentAddress: agentAddress.toLowerCase(),
      latestNonce: latestNonce,
      nextNonce: nextNonce
    });
  } catch (error) {
    console.error('Error fetching execNonce:', error);
    res.status(500).json({ error: 'Failed to fetch execNonce' });
  }
});

// POST a new transaction (client-facing endpoint)
app.post('/api/transactions/add', async (req, res) => {
  try {
    const newTransaction: CCIPTransaction = req.body;
    console.log('inbound newTransaction: ', newTransaction);

    // Validate transaction type before proceeding
    const validTypes = [
      'deposit',
      'depositAndMintEigenAgent',
      'mintEigenAgent',
      'queueWithdrawal',
      'completeWithdrawal',
      'processClaim',
      'bridgingWithdrawalToL2',
      'bridgingRewardsToL2',
      'delegateTo',
      'undelegate',
      'redelegate',
      'other'
    ];
    if (!validTypes.includes(newTransaction.txType)) {
      console.error(`Invalid transaction type: ${newTransaction.txType}. Valid types are: ${validTypes.join(', ')}`);
      return res.status(400).json({
        error: `Invalid transaction type: ${newTransaction.txType}. Valid types are: ${validTypes.join(', ')}`
      });
    }

    // Ensure required fields have values
    if (!newTransaction.sourceChainId) {
      console.log(`No sourceChainId provided for tx ${newTransaction.txHash}, setting default based on type`);
      // Set default source chain ID based on transaction type
      if (
        newTransaction.txType === 'bridgingWithdrawalToL2' ||
        newTransaction.txType === 'bridgingRewardsToL2'
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

    // If an execNonce is provided, ensure it's a number
    if (newTransaction.execNonce !== undefined) {
      // Make sure it's a number
      newTransaction.execNonce = Number(newTransaction.execNonce);
      console.log(`Transaction includes execNonce: ${newTransaction.execNonce}`);
    }

    // Continue with extracting messageId if needed
    if (!newTransaction.messageId && newTransaction.txHash) {
      try {
        console.log(`Transaction ${newTransaction.txHash} doesn't have a messageId. Attempting to extract...`);

        // Determine which client to use based on transaction type or chainId
        const client = determineClientFromTransaction(newTransaction);

        // Extract messageId from the transaction receipt
        const { messageId, agentOwner } = await extractMessageIdFromTxHash(newTransaction.txHash, client);

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
    const errorResponse = error as ErrorResponse;
    console.error('Error adding transaction:', error);
    // Provide more specific error message for constraint violations
    if (errorResponse.code === 'SQLITE_CONSTRAINT_CHECK') {
      return res.status(400).json({
        error: 'Invalid transaction data. Check that the transaction type and status are valid values.',
        details: errorResponse.message
      });
    }
    res.status(500).json({ error: 'Failed to add transaction', details: errorResponse.message });
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
  switch (transaction.txType) {
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

// Load operator keys from environment variables
const OPERATOR_KEYS: { [key: string]: string | undefined } = {};
for (let i = 1; i <= 10; i++) {
  const keyName = `OPERATOR_KEY${i}`;
  if (process.env[keyName]) {
    OPERATOR_KEYS[keyName] = process.env[keyName];
  }
}

// Validate that at least one operator key is set
if (Object.keys(OPERATOR_KEYS).length === 0) {
  console.warn('Warning: No operator keys found in environment variables (OPERATOR_KEY1 through OPERATOR_KEY10)');
}

// Create a map of operator addresses to their private keys
const operatorAddressToKey = new Map<string, string>();

// Initialize operator addresses
Object.entries(OPERATOR_KEYS).forEach(([keyName, privateKey]) => {
  if (privateKey) {
    try {
      const account = privateKeyToAccount(privateKey as `0x${string}`);
      operatorAddressToKey.set(account.address.toLowerCase(), privateKey);
      console.log(`Initialized operator ${keyName} with address ${account.address}`);
    } catch (error) {
      console.error(`Error initializing operator account for ${keyName}:`, error);
    }
  }
});


// Update the endpoint before starting the server
app.post('/api/delegation/sign', async (req, res) => {
  try {
    const { staker, operator } = req.body;

    // Validate input parameters
    if (!staker || !operator) {
      return res.status(400).json({
        error: 'Missing required parameters'
      });
    }

    // Validate addresses
    if (!staker.startsWith('0x') || !operator.startsWith('0x')) {
      return res.status(400).json({
        error: 'Invalid address format'
      });
    }

    // Get operator key from map. Only for testing purposes.
    // In production we query Eigenlayer's API to sign the message.
    const operatorKey = operatorAddressToKey.get(operator.toLowerCase());
    if (!operatorKey) {
      return res.status(401).json({
        error: 'Unauthorized operator address'
      });
    }

    // Set expiry to 7 days from now
    const expiry = BigInt(Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60);

    const result = await signDelegationApproval(staker, operator, operatorKey as `0x${string}`, expiry);

    res.json(result);
  } catch (error) {
    const errorResponse = error as ErrorResponse;
    console.error('Error in delegation signing endpoint:', error);
    // Return a 401 status if the operator is not authorized
    if (errorResponse.message === 'Unauthorized operator address') {
      return res.status(401).json({
        error: 'Unauthorized operator address'
      });
    }

    res.status(500).json({
      error: 'Failed to sign delegation approval',
      details: errorResponse.message
    });
  }
});

interface ErrorResponse {
  message?: string;
  details?: string;
  code?: string;
  shortMessage?: string;
}

// Define the Operator type
interface Operator {
  name: string;
  address: string;
  magicStaked: string;
  ethStaked: string;
  stakers: number;
  fee: string;
  isActive: boolean;
}

// Operator data
const OPERATORS_DATA: Operator[] = [
  {
    address: '0xA4D423ED017F063AaF65f6B6B9C6Bc59f97d5164',
    name: 'Treasure Node 1',
    magicStaked: '1,250,000',
    ethStaked: '432.5',
    stakers: 42,
    fee: '1%',
    isActive: true
  },
  {
    address: '0xaA61cC14ac3e048f26b9312E57ECf8156D9D27e3',
    name: 'Treasure Node2',
    magicStaked: '890,500',
    ethStaked: '122.2',
    stakers: 36,
    fee: '2%',
    isActive: true
  },
  {
    address: '0x3d2FB9D26c5C66D0CA55247E4d40Cb4FBe0f5C03',
    name: "Inactive Operator",
    magicStaked: '2,100,000',
    ethStaked: '95.8',
    stakers: 65,
    fee: '4%',
    isActive: false
  }
];

// Create a map to quickly look up operators by address
const operatorsByAddress = new Map<string, Operator>();
OPERATORS_DATA.forEach(operator => {
  operatorsByAddress.set(operator.address.toLowerCase(), operator);
});

// Add endpoint to get all operators
app.get('/api/operators', (req, res) => {
  try {
    // Return only active operators by default
    const showInactive = req.query.showInactive === 'true';
    const operators = showInactive
      ? OPERATORS_DATA
      : OPERATORS_DATA.filter(op => op.isActive);

    res.json(operators);
  } catch (error) {
    console.error('Error fetching operators:', error);
    res.status(500).json({ error: 'Failed to fetch operators' });
  }
});

// Add endpoint to get operator by address
app.get('/api/operators/:address', (req, res) => {
  try {
    const { address } = req.params;
    const operator = operatorsByAddress.get(address.toLowerCase());

    if (!operator) {
      return res.status(404).json({ error: 'Operator not found' });
    }

    res.json(operator);
  } catch (error) {
    console.error('Error fetching operator:', error);
    res.status(500).json({ error: 'Failed to fetch operator' });
  }
});


// Serve static files from the 'dist' directory (for production)
if (process.env.NODE_ENV === 'production') {
  app.use(express.static(path.join(__dirname, 'dist')));

  app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'dist', 'index.html'));
  });
}

// Create HTTP server that redirects to HTTPS
const httpServer = express();
httpServer.use((req, res) => {
  res.redirect(`https://${req.hostname}:${PORT}${req.url}`);
});
httpServer.listen(80, '0.0.0.0', () => {
  console.log('HTTP server running on port 80 (redirecting to HTTPS)');
});

// Create HTTPS server
const httpsServer = https.createServer(sslOptions, app);

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
      } else if (tx.messageId === tx.txHash) {
        // For transactions where messageId is the same as txHash
        throw new Error('MessageId cannot be the same as the transaction hash');
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
    // Check every 20 seconds
    pendingTxIntervalId = setInterval(updatePendingTransactions, 20 * 1000);
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
  httpsServer.close(() => {
    console.log('HTTPS server closed');
    process.exit(0);
  });
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received. Shutting down server gracefully...');
  stopPendingTransactionChecker();
  httpsServer.close(() => {
    console.log('HTTPS server closed');
    process.exit(0);
  });
});

// After initializing the server, fix any transactions with missing fields
httpsServer.listen({
  port: PORT,
  host: '0.0.0.0'
}, () => {
  console.log(`🚀 HTTPS Server running at https://api.l2restaking.info:${PORT}`);

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
                  tx.txType = tx.txType || 'other';
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

// Socket.io connection handling
const io = new Server(httpsServer, {
  cors: {
    origin: [
      'https://l2-eigenlayer-restaking-git-frontend-peita-lins-projects.vercel.app',
      /\.vercel\.app$/,
      'http://localhost:5173',
      'http://localhost:3000'
    ],
    methods: ['GET', 'POST']
  }
});

// Socket.io connection handling
io.on('connection', (socket: Socket) => {
  console.log('Client connected');
  socket.on('disconnect', () => console.log('Client disconnected'));
});
