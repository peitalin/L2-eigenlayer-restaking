import express from 'express';
import * as db from '../db';
import { ErrorResponse, validTxTypes } from '../types';
import { ETH_CHAINID, L2_CHAINID } from '../utils/constants';
import { extractMessageIdFromTxHash, updateTransactionStatus } from '../utils/transaction';
import { determineClientFromTransaction } from '../utils/clients';
import type { Transaction } from '../db';
import logger from '../utils/logger';

const router = express.Router();

// GET transactions by user address
router.get('/user/:address', (req, res) => {
  try {
    const { address } = req.params;
    const transactions = db.getTransactionsByUser(address);
    res.json(transactions);
  } catch (error) {
    logger.error('Error fetching user transactions:', error);
    res.status(500).json({ error: 'Failed to fetch user transactions' });
  }
});

// GET transaction by hash
router.get('/hash/:txHash', (req, res) => {
  try {
    const { txHash } = req.params;
    const transaction = db.getTransactionByHash(txHash);

    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    res.json(transaction);
  } catch (error) {
    logger.error('Error fetching transaction by hash:', error);
    res.status(500).json({ error: 'Failed to fetch transaction' });
  }
});

// GET transaction by messageId
router.get('/messageId/:messageId', (req, res) => {
  try {
    const { messageId } = req.params;
    const transaction = db.getTransactionByMessageId(messageId);

    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    res.json(transaction);
  } catch (error) {
    logger.error('Error fetching transaction by messageId:', error);
    res.status(500).json({ error: 'Failed to fetch transaction' });
  }
});

// POST a new transaction (client-facing endpoint)
router.post('/add', async (req, res) => {
  try {
    const newTransaction: Transaction = req.body;
    logger.info('inbound newTransaction: ', newTransaction);

    if (!validTxTypes.includes(newTransaction.txType)) {
      logger.error(`Invalid transaction type: ${newTransaction.txType}. Valid types are: ${validTxTypes.join(', ')}`);
      return res.status(400).json({
        error: `Invalid transaction type: ${newTransaction.txType}. Valid types are: ${validTxTypes.join(', ')}`
      });
    }

    // Ensure required fields have values
    if (!newTransaction.sourceChainId) {
      logger.info(`No sourceChainId provided for tx ${newTransaction.txHash}, setting default based on type`);
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
      logger.info(`No destinationChainId provided for transaction ${newTransaction.txHash}, setting default based on type`);
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
      logger.info(`Transaction includes execNonce: ${newTransaction.execNonce}`);
    }

    // Continue with extracting messageId if needed
    if (!newTransaction.messageId && newTransaction.txHash) {
      try {
        logger.info(`Transaction ${newTransaction.txHash} doesn't have a messageId. Attempting to extract...`);

        // Determine which client to use based on transaction type or chainId
        const client = determineClientFromTransaction(newTransaction);

        // Extract messageId from the transaction receipt
        const { messageId, agentOwner } = await extractMessageIdFromTxHash(newTransaction.txHash, client);

        if (messageId) {
          logger.info(`Successfully extracted messageId ${messageId} from transaction ${newTransaction.txHash}`);
          newTransaction.messageId = messageId;

          // If we found an agent owner and the transaction doesn't have a user field
          if (agentOwner && (!newTransaction.user || newTransaction.user === '0x0000000000000000000000000000000000000000')) {
            newTransaction.user = agentOwner;
          }
        } else {
          // If no messageId found, use txHash as the messageId
          logger.info(`No messageId found for transaction ${newTransaction.txHash}, using txHash as messageId`);
          newTransaction.messageId = newTransaction.txHash;
        }
      } catch (extractError) {
        logger.error(`Error extracting messageId from transaction ${newTransaction.txHash}:`, extractError);
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
          logger.error(`Error updating transaction status for ${newTransaction.messageId}:`, updateError);
        }
      }, 2000);
    }

    res.json({ success: true, transaction: savedTransaction });
  } catch (error) {
    const errorResponse = error as ErrorResponse;
    logger.error('Error adding transaction:', error);
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

export default router;
