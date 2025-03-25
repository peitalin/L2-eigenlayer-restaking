import express from 'express';
import cors from 'cors';
import https from 'https';
import * as nodeHttp from 'http';
import { config } from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { promises as fsPromises } from 'fs';
import { createPublicClient, http, PublicClient } from 'viem';
import { sepolia, baseSepolia } from 'viem/chains';
import { signDelegationApproval } from './signers/signDelegationApproval';
import * as db from './db';
import { router } from './routes';
import { fetchCCIPMessageData } from './utils/ccip';
import { ErrorResponse } from './types';
import { ETH_CHAINID, L2_CHAINID } from './utils/constants';
import {
  OPERATORS_DATA,
  operatorsByAddress,
  operatorAddressToKey,
} from './utils/operators';
import { extractMessageIdFromTxHash, updateTransactionStatus } from './utils/transaction';
import logger from './utils/logger';
import transactionsRouter from './routes/transactions';

// Load environment variables
config();

// Validate required environment variables
const requiredEnvVars = ['DELEGATION_MANAGER_ADDRESS'];
const missingEnvVars = requiredEnvVars.filter(varName => !process.env[varName]);
if (missingEnvVars.length > 0) {
  throw new Error(`Missing required environment variables: ${missingEnvVars.join(', ')}`);
}

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

// Environment variable to control SSL usage
const USE_SSL = process.env.USE_SSL === 'true';
console.log(`Server running with SSL: ${USE_SSL ? 'ENABLED' : 'DISABLED'}`);

// SSL configuration only when enabled
let sslOptions;
if (USE_SSL) {
  try {
    console.log('Loading SSL certificates...');
    sslOptions = {
      key: fs.readFileSync('/etc/letsencrypt/live/api.l2restaking.info/privkey.pem'),
      cert: fs.readFileSync('/etc/letsencrypt/live/api.l2restaking.info/fullchain.pem'),
    };
    console.log('SSL certificates loaded successfully');
  } catch (error) {
    console.error('Failed to load SSL certificates:', error);
    console.log('Falling back to HTTP mode');
    process.env.USE_SSL = 'false';
  }
}

// Middleware
app.use(cors({
  origin: [
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
app.use('/api/transactions', transactionsRouter);

// Data storage path - ensure the data directory exists for SQLite
const dataDir = path.join(__dirname, '..', 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

// Create public clients to interact with different chains
const publicClientL1 = createPublicClient({
  chain: sepolia,
  transport: http(process.env.SEPOLIA_RPC_URL || 'https://ethereum-sepolia.publicnode.com')
});


// Define the transaction history interface (now we use the one from db.ts)
export type CCIPTransaction = db.Transaction;

// Create a second client for Base Sepolia (L2)
const publicClientL2 = createPublicClient({
  chain: baseSepolia,
  transport: http(process.env.BASE_SEPOLIA_RPC_URL || 'https://sepolia.base.org')
});


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

// // GET all transactions
// app.get('/api/transactions', (req, res) => {
//   try {
//     const transactions = db.getAllTransactions();
//     res.json(transactions);
//   } catch (error) {
//     console.error('Error reading transaction history:', error);
//     res.status(500).json({ error: 'Failed to read transaction history' });
//   }
// });

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
export function determineClientFromTransaction(transaction: CCIPTransaction): PublicClient {
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

// Create either HTTP or HTTPS server
let server;
try {
  if (USE_SSL && sslOptions) {
    console.log('Creating HTTPS server...');
    server = https.createServer(sslOptions, app);
    console.log('HTTPS server created successfully');
  } else {
    console.log('Creating HTTP server...');
    server = nodeHttp.createServer(app);
    console.log('HTTP server created successfully');
  }
} catch (error) {
  console.error('Failed to create server:', error);
  process.exit(1); // Exit if server creation fails
}

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
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

process.on('SIGTERM', () => {
  console.log('SIGTERM received. Shutting down server gracefully...');
  stopPendingTransactionChecker();
  server.close(() => {
    console.log('Server closed');
    process.exit(0);
  });
});

// After initializing the server, fix any transactions with missing fields
try {
  server.listen(Number(PORT), '0.0.0.0', () => {
    const protocol = USE_SSL ? 'https' : 'http';
    console.log(`🚀 Server running at ${protocol}://api.l2restaking.info:${PORT}`);

    // Run an initial update when the server starts
    updatePendingTransactions();
    startPendingTransactionChecker();
  });

  server.on('error', (error: Error) => {
    console.error('Server error:', error);
  });
} catch (error) {
  console.error('Failed to start server:', error);
  process.exit(1);
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
