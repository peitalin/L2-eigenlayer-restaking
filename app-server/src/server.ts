import express from 'express';
import cors from 'cors';
import https from 'https';
import * as nodeHttp from 'http';
import { config } from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { promises as fsPromises } from 'fs';
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
import { updateTransactionStatus } from './utils/transaction';
import logger from './utils/logger';
import transactionsRouter from './routes/transactions';
import ccipRouter from './routes/ccip';
import execnonceRouter from './routes/execnonce';
import delegationRouter from './routes/delegation';
import operatorsRouter from './routes/operators';
import { publicClientL1, publicClientL2 } from './utils/clients';

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
 * GET /api/ccip/message/:messageId
 * GET /api/transactions/user/:address
 * GET /api/transactions/hash/:txHash
 * GET /api/transactions/messageId/:messageId
 * GET /api/execnonce/:agentAddress
 * POST /api/transactions/add
 * POST /api/delegation/sign
 * GET /api/operators
 * GET /api/operators/:address
 */

// Get the directory name
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Initialize express app
export const app = express();
const PORT = process.env.SERVER_PORT || 3001;

// Environment variable to control SSL usage
const USE_SSL = process.env.USE_SSL === 'true';
logger.info(`Server running with SSL: ${USE_SSL ? 'ENABLED' : 'DISABLED'}`);

// SSL configuration only when enabled
let sslOptions;
if (USE_SSL) {
  try {
    logger.info('Loading SSL certificates...');
    sslOptions = {
      key: fs.readFileSync('/etc/letsencrypt/live/api.l2restaking.info/privkey.pem'),
      cert: fs.readFileSync('/etc/letsencrypt/live/api.l2restaking.info/fullchain.pem'),
    };
    logger.info('SSL certificates loaded successfully');
  } catch (error) {
    logger.warn('Failed to load SSL certificates. Falling back to HTTP mode');
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

// Routes
app.use('/api', router);
app.use('/api/transactions', transactionsRouter);
app.use('/api/ccip', ccipRouter);
app.use('/api/execnonce', execnonceRouter);
app.use('/api/delegation', delegationRouter);
app.use('/api/operators', operatorsRouter);

// Data storage path - ensure the data directory exists for SQLite
const dataDir = path.join(__dirname, '..', 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

// Define the transaction history interface (now we use the one from db.ts)
export type CCIPTransaction = db.Transaction;

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
    logger.info('Creating HTTPS server...');
    server = https.createServer(sslOptions, app);
    logger.info('HTTPS server created successfully');
  } else {
    logger.info('Creating HTTP server...');
    server = nodeHttp.createServer(app);
    logger.info('HTTP server created successfully');
  }
} catch (error) {
  logger.error('Failed to create server:', error);
  process.exit(1); // Exit if server creation fails
}

// Function to check and update pending transactions
async function updatePendingTransactions() {
  try {
    const pendingTransactions = db.getPendingTransactions();

    if (pendingTransactions.length === 0) {
      return;
    }

    logger.debug(`Checking ${pendingTransactions.length} pending transactions...`);

    for (const tx of pendingTransactions) {
      // If the transaction has a messageId that's different from txHash, check its status
      if (tx.messageId && tx.messageId !== tx.txHash) {
        try {
          const messageData = await fetchCCIPMessageData(tx.messageId);

          if (messageData) {
            // Update transaction status based on message data
            if (messageData.status === 'SUCCESS') {
              logger.info(`Transaction ${tx.txHash} (messageId: ${tx.messageId}) completed successfully`);
              db.updateTransactionByMessageId(tx.messageId, {
                status: 'confirmed',
                isComplete: true,
                receiptTransactionHash: messageData.destTxHash || tx.receiptTransactionHash
              });
            } else if (messageData.status === 'FAILED') {
              logger.warn(`Transaction ${tx.txHash} (messageId: ${tx.messageId}) failed`);
              db.updateTransactionByMessageId(tx.messageId, {
                status: 'failed',
                isComplete: true
              });
            } else {
              logger.debug(`Transaction ${tx.txHash} (messageId: ${tx.messageId}) is still ${messageData.status}`);
              // No update needed for in-progress transactions
            }
          }
        } catch (error) {
          logger.error(`Error updating transaction ${tx.txHash} (messageId: ${tx.messageId}):`, error);
        }
      } else if (tx.messageId === tx.txHash) {
        // For transactions where messageId is the same as txHash
        throw new Error('MessageId cannot be the same as the transaction hash');
      }
    }
  } catch (error) {
    logger.error('Error checking pending transactions:', error);
  }
}

// Start the pending transaction checker
let pendingTxIntervalId: NodeJS.Timeout | null = null;

function startPendingTransactionChecker() {
  if (pendingTxIntervalId === null) {
    // Check every 20 seconds
    pendingTxIntervalId = setInterval(updatePendingTransactions, 20 * 1000);
    logger.info('Started pending transaction checker');

    // Also run immediately
    updatePendingTransactions();
  }
}

function stopPendingTransactionChecker() {
  if (pendingTxIntervalId !== null) {
    clearInterval(pendingTxIntervalId);
    pendingTxIntervalId = null;
    logger.info('Stopped pending transaction checker');
  }
}

// Only start the server and checker if not in test mode
const isTestMode = process.env.NODE_ENV === 'test';
if (!isTestMode) {
  try {
    server.listen(Number(PORT), '0.0.0.0', () => {
      const protocol = USE_SSL ? 'https' : 'http';
      logger.info(`🚀 Server running at ${protocol}://api.l2restaking.info:${PORT}`);

      // Run an initial update when the server starts
      updatePendingTransactions();
      startPendingTransactionChecker();
    });

    server.on('error', (error: Error) => {
      logger.error('Server error:', error);
    });
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }

  // Clean shutdown handler
  process.on('SIGINT', () => {
    logger.info('Shutting down server gracefully...');
    stopPendingTransactionChecker();
    server.close(() => {
      logger.info('Server closed');
      process.exit(0);
    });
  });

  process.on('SIGTERM', () => {
    logger.info('SIGTERM received. Shutting down server gracefully...');
    stopPendingTransactionChecker();
    server.close(() => {
      logger.info('Server closed');
      process.exit(0);
    });
  });
} else {
  logger.info('Running in test mode - not starting server');
}

// Database initialization
try {
  fsPromises.mkdir(dataDir, { recursive: true }).then(() => {
    logger.info('Data directory created or confirmed');

    // Check if we need to migrate existing data
    fs.access(path.join(dataDir, 'transactions.json'), fs.constants.F_OK, (err) => {
      if (!err) {
        logger.info('Found existing transactions.json file, migrating to SQLite...');
        fs.readFile(path.join(dataDir, 'transactions.json'), 'utf8', (err, data) => {
          if (err) {
            logger.error('Error reading transactions file:', err);
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

                logger.info(`Found ${transactionsData.length} transactions, ${validTransactions.length} are valid`);

                if (validTransactions.length > 0) {
                  db.addTransactions(validTransactions);
                  logger.info(`Migrated ${validTransactions.length} transactions to SQLite database`);
                }
              } else {
                logger.info('No transactions to migrate');
              }
            } catch (parseError) {
              logger.error('Error parsing transactions file:', parseError);
            }
          }
        });
      } else {
        logger.info('No existing transactions.json file found');
      }
    });
  });
} catch (error) {
  logger.error('Error initializing database:', error);
}
