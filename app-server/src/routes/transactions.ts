import express from 'express';
import * as db from '../db';
import { ErrorResponse } from '../types';
import { ETH_CHAINID, L2_CHAINID } from '../utils/constants';
import { extractMessageIdFromTxHash, updateTransactionStatus } from '../utils/transaction';
import { determineClientFromTransaction } from '../utils/clients';
import type { Transaction } from '../db';

const router = express.Router();

// GET transactions by user address
router.get('/user/:address', (req, res) => {
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
router.get('/hash/:txHash', (req, res) => {
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
router.get('/messageId/:messageId', (req, res) => {
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
router.post('/add', async (req, res) => {
  try {
    const newTransaction: Transaction = req.body;
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

// PUT update a transaction (server-side only - not exposed to frontend)
router.put('/:txHash', (req, res) => {
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
router.put('/messageId/:messageId', (req, res) => {
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


export default router;
