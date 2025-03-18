import express from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { config } from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { createPublicClient, http, decodeEventLog, PublicClient } from 'viem';
import { sepolia } from 'viem/chains';

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

// Data storage path for transaction history
const dataDir = path.join(__dirname, 'data');
const txHistoryPath = path.join(dataDir, 'transactions.json');

// Create data directory if it doesn't exist
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

// Initialize transaction history if it doesn't exist
if (!fs.existsSync(txHistoryPath)) {
  fs.writeFileSync(txHistoryPath, JSON.stringify([]));
}

// Define types for CCIP message data (copied from frontend)
interface CCIPMessageData {
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

// Define the transaction history interface
interface CCIPTransaction {
  txHash: string;
  messageId: string;
  timestamp: number;
  type: 'deposit' | 'withdrawal' | 'completeWithdrawal' | 'bridgingWithdrawalToL2' | 'other';
  status: 'pending' | 'confirmed' | 'failed';
  from: string;
  to: string;
  receiptTransactionHash?: string;
}

// MessageSent event signature for CCIP transactions
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

// Add this constant for the MessageSent event signature
const MESSAGE_SENT_SIGNATURE = '0xf41bc76bbe18ec95334bdb88f45c769b987464044ead28e11193a766ae8225cb';

// Create a public client to interact with the chain
const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(process.env.SEPOLIA_RPC_URL || 'https://ethereum-sepolia.publicnode.com')
});

// Helper function to fetch CCIP message data
const fetchCCIPMessageData = async (messageId: string): Promise<CCIPMessageData | null> => {
  try {
    console.log(`Fetching CCIP data for messageId: ${messageId}`);
    const response = await fetch(`https://ccip.chain.link/api/h/atlas/message/${messageId}`);

    if (!response.ok) {
      console.error(`Error fetching CCIP data: ${response.status} ${response.statusText}`);
      return null;
    }

    const data = await response.json();
    return data as CCIPMessageData;
  } catch (error) {
    console.error('Error fetching CCIP message data:', error);
    return null;
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

// Get transaction history
app.get('/api/transactions', (req, res) => {
  try {
    const transactions = JSON.parse(fs.readFileSync(txHistoryPath, 'utf-8'));
    res.json(transactions);
  } catch (error) {
    console.error('Error reading transaction history:', error);
    res.status(500).json({ error: 'Failed to read transaction history' });
  }
});

// Save transaction history
app.post('/api/transactions', (req, res) => {
  try {
    const transactions = req.body;
    fs.writeFileSync(txHistoryPath, JSON.stringify(transactions, null, 2));
    res.json({ success: true });
  } catch (error) {
    console.error('Error saving transaction history:', error);
    res.status(500).json({ error: 'Failed to save transaction history' });
  }
});

// Add a new transaction
app.post('/api/transactions/add', (req, res) => {
  try {
    const newTransaction: CCIPTransaction = req.body;
    const transactions: CCIPTransaction[] = JSON.parse(fs.readFileSync(txHistoryPath, 'utf-8'));

    // Check if transaction already exists
    const existingTx = transactions.find(tx => tx.txHash === newTransaction.txHash);
    if (existingTx) {
      // Update the existing transaction
      Object.assign(existingTx, newTransaction);
    } else {
      // Add the new transaction
      transactions.push(newTransaction);
    }

    fs.writeFileSync(txHistoryPath, JSON.stringify(transactions, null, 2));
    res.json({ success: true, transaction: newTransaction });
  } catch (error) {
    console.error('Error adding transaction:', error);
    res.status(500).json({ error: 'Failed to add transaction' });
  }
});

// Update a transaction
app.put('/api/transactions/:txHash', (req, res) => {
  try {
    const { txHash } = req.params;
    const updates = req.body;

    const transactions: CCIPTransaction[] = JSON.parse(fs.readFileSync(txHistoryPath, 'utf-8'));
    const txIndex = transactions.findIndex(tx => tx.txHash === txHash);

    if (txIndex === -1) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    transactions[txIndex] = { ...transactions[txIndex], ...updates };
    fs.writeFileSync(txHistoryPath, JSON.stringify(transactions, null, 2));

    res.json({ success: true, transaction: transactions[txIndex] });
  } catch (error) {
    console.error('Error updating transaction:', error);
    res.status(500).json({ error: 'Failed to update transaction' });
  }
});

// Update a transaction by messageId
app.put('/api/transactions/messageId/:messageId', (req, res) => {
  try {
    const { messageId } = req.params;
    const updates = req.body;

    const transactions: CCIPTransaction[] = JSON.parse(fs.readFileSync(txHistoryPath, 'utf-8'));
    const txIndex = transactions.findIndex(tx => tx.messageId === messageId);

    if (txIndex === -1) {
      return res.status(404).json({ error: 'Transaction not found' });
    }

    transactions[txIndex] = { ...transactions[txIndex], ...updates };
    fs.writeFileSync(txHistoryPath, JSON.stringify(transactions, null, 2));

    res.json({ success: true, transaction: transactions[txIndex] });
  } catch (error) {
    console.error('Error updating transaction:', error);
    res.status(500).json({ error: 'Failed to update transaction' });
  }
});

// Clear transaction history
app.delete('/api/transactions', (req, res) => {
  try {
    fs.writeFileSync(txHistoryPath, JSON.stringify([]));
    res.json({ success: true });
  } catch (error) {
    console.error('Error clearing transaction history:', error);
    res.status(500).json({ error: 'Failed to clear transaction history' });
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

    // Step 3: Get the receipt transaction to check for MessageSent events
    try {
      console.log(`Getting transaction receipt for: ${messageData.receiptTransactionHash}`);
      const receipt = await publicClient.getTransactionReceipt({
        hash: messageData.receiptTransactionHash as `0x${string}`
      });

      console.log(`Receipt contains ${receipt.logs.length} logs`);

      // Step 4: Look for MessageSent events in the receipt
      let newMessageId: string | null = null;

      // Find logs that contain the MessageSent event
      for (const log of receipt.logs) {
        console.log(`Checking log with topics: ${JSON.stringify(log.topics)}`);
        console.log(`Looking for topic[0] = ${MESSAGE_SENT_SIGNATURE}`);

        // Check if this log is for a MessageSent event (comparing the first topic with the event signature)
        if (log.topics[0] === MESSAGE_SENT_SIGNATURE && log.topics.length >= 2) {
          // The messageId is the first indexed parameter (second topic)
          // Ensure messageId is a string
          newMessageId = log.topics[1] ? log.topics[1].toString() : null;
          console.log(`Found MessageSent event with new messageId: ${newMessageId}`);
          break;
        }
      }
      console.log('New messageId:', newMessageId);

      // After the first attempt to find MessageSent event
      if (!newMessageId) {
        console.log('No MessageSent event found by topic signature, trying ABI decoding approach...');

        // Try to decode each log with the MessageSent ABI
        for (const log of receipt.logs) {
          try {
            const decodedLog = decodeEventLog({
              abi: [MESSAGE_SENT_EVENT],
              data: log.data,
              topics: log.topics as any
            });

            console.log('Successfully decoded log:', decodedLog);

            // Check if this is a MessageSent event
            if (decodedLog.eventName === 'MessageSent' && decodedLog.args) {
              // Extract the messageId from the decoded log
              // Type assertion to handle the unknown type of args
              const args = decodedLog.args as any;
              newMessageId = args.messageId ? args.messageId.toString() : null;
              console.log(`Found MessageSent event using ABI decoding. MessageId: ${newMessageId}`);
              break;
            }
          } catch (decodeError) {
            // Log the error and continue to the next log
            console.log('Failed to decode log:', decodeError.message);
            continue;
          }
        }
      }

      console.log('Final messageId determination:', newMessageId);

      // Step 5: If we found a new messageId, fetch its data
      if (newMessageId) {
        console.log(`Found new messageId: ${newMessageId}, fetching details...`);

        // Use our helper function to fetch the CCIP message data
        const newMessageData = await fetchCCIPMessageData(newMessageId);
        let newTxHash: string | null = null;
        let bridgingTransactionData: CCIPTransaction | null = null;

        if (newMessageData) {
          newTxHash = newMessageData.sendTransactionHash;
          console.log(`Found transaction hash for new message: ${newTxHash}`);

          // Create bridging transaction data with proper validation
          if (newTxHash) {
            bridgingTransactionData = {
              txHash: newTxHash,
              messageId: newMessageId,
              timestamp: Math.floor(Date.now() / 1000),
              type: 'bridgingWithdrawalToL2' as const,
              status: 'pending' as const,
              from: messageData.receiver || '0x0000000000000000000000000000000000000000',
              to: messageData.receiver || '0x0000000000000000000000000000000000000000'
            } as CCIPTransaction;
            console.log('Created bridging transaction data:', bridgingTransactionData);
          }
        } else {
          console.warn(`Could not fetch data for new messageId ${newMessageId}`);
        }

        // Read the current transaction history
        const transactions: CCIPTransaction[] = JSON.parse(fs.readFileSync(txHistoryPath, 'utf-8'));

        // Find the original completeWithdrawal transaction
        const txIndex = transactions.findIndex(tx => tx.txHash === originalTxHash);

        if (txIndex !== -1) {
          // Update the original transaction as confirmed and add receiptTransactionHash
          transactions[txIndex] = {
            ...transactions[txIndex],
            status: 'confirmed',
            receiptTransactionHash: messageData.receiptTransactionHash as string
          };

          // Add a new transaction for the bridging event if we have the data
          if (bridgingTransactionData) {
            // Check if this transaction already exists
            const existingTxIndex = transactions.findIndex(tx => tx.txHash === bridgingTransactionData?.txHash);
            if (existingTxIndex === -1) {
              // Only add if it doesn't already exist
              transactions.push(bridgingTransactionData);
              console.log(`Added new bridging transaction with hash: ${bridgingTransactionData.txHash}`);
            } else {
              console.log(`Bridging transaction with hash ${bridgingTransactionData.txHash} already exists`);
            }
          }

          // Save the updated transaction history
          fs.writeFileSync(txHistoryPath, JSON.stringify(transactions, null, 2));
          console.log('Transaction history updated successfully');

          return res.json({
            isComplete: true,
            updatedOriginalTx: transactions[txIndex],
            bridgingTransaction: bridgingTransactionData,
            newMessageId
          });
        } else {
          return res.status(404).json({
            error: 'Original transaction not found in history',
            isComplete: true,
            originalTxUpdated: false
          });
        }
      } else {
        // No MessageSent event found, but transaction completed
        // Just update the original transaction status
        const transactions: CCIPTransaction[] = JSON.parse(fs.readFileSync(txHistoryPath, 'utf-8'));
        const txIndex = transactions.findIndex(tx => tx.txHash === originalTxHash);

        if (txIndex !== -1) {
          // Update with receiptTransactionHash
          transactions[txIndex] = {
            ...transactions[txIndex],
            status: 'confirmed',
            receiptTransactionHash: messageData.receiptTransactionHash as string
          };

          fs.writeFileSync(txHistoryPath, JSON.stringify(transactions, null, 2));

          return res.json({
            isComplete: true,
            updatedOriginalTx: transactions[txIndex],
            newTxAdded: false,
            message: 'No bridging transaction detected, but original withdrawal marked as complete'
          });
        } else {
          return res.status(404).json({
            error: 'Original transaction not found in history',
            isComplete: true,
            originalTxUpdated: false
          });
        }
      }
    } catch (receiptError) {
      console.error(`Error getting receipt for transaction: ${messageData.receiptTransactionHash}`, receiptError);
      return res.status(500).json({
        error: `Failed to get transaction receipt: ${receiptError.message}`
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

    const txHash = messageData.sendTransactionHash;
    if (!txHash) {
      return res.status(400).json({
        error: 'No transaction hash found in CCIP message data'
      });
    }

    // Read transaction history
    const transactions: CCIPTransaction[] = JSON.parse(fs.readFileSync(txHistoryPath, 'utf-8'));

    // Create bridging transaction
    const bridgingTransaction: CCIPTransaction = {
      txHash: txHash,
      messageId: messageId,
      timestamp: Math.floor(Date.now() / 1000),
      type: 'bridgingWithdrawalToL2',
      status: 'pending',
      from: messageData.sender || '0x0000000000000000000000000000000000000000',
      to: messageData.receiver || '0x0000000000000000000000000000000000000000'
    };

    // Check if transaction already exists
    const existingTxIndex = transactions.findIndex(tx => tx.txHash === txHash);

    if (existingTxIndex !== -1) {
      // Update existing transaction
      transactions[existingTxIndex] = {
        ...transactions[existingTxIndex],
        ...bridgingTransaction
      };
      console.log(`Updated existing bridging transaction: ${txHash}`);
    } else {
      // Add new transaction
      transactions.push(bridgingTransaction);
      console.log(`Added new bridging transaction: ${txHash}`);
    }

    // If original transaction hash is provided, update it too
    if (originalTxHash) {
      const originalTxIndex = transactions.findIndex(tx => tx.txHash === originalTxHash);
      if (originalTxIndex !== -1) {
        transactions[originalTxIndex] = {
          ...transactions[originalTxIndex],
          status: 'confirmed',
          receiptTransactionHash: messageData.receiptTransactionHash as string
        };
        console.log(`Updated original transaction: ${originalTxHash}`);
      }
    }

    // Save updated transaction history
    fs.writeFileSync(txHistoryPath, JSON.stringify(transactions, null, 2));

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

// Serve static files from the 'dist' directory (for production)
if (process.env.NODE_ENV === 'production') {
  app.use(express.static(path.join(__dirname, 'dist')));

  app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'dist', 'index.html'));
  });
}

// Start the server
const httpServer = createServer(app);

httpServer.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
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