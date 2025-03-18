import express from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { config } from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

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
  type: 'deposit' | 'withdrawal' | 'completeWithdrawal' | 'other';
  status: 'pending' | 'confirmed' | 'failed';
  from: string;
  to: string;
}

// API Routes

// Fetch CCIP message data
app.get('/api/ccip/message/:messageId', async (req, res) => {
  const { messageId } = req.params;

  if (!messageId) {
    return res.status(400).json({ error: 'No messageId provided' });
  }

  try {
    console.log(`Fetching CCIP data for messageId: ${messageId}`);
    const response = await fetch(`https://ccip.chain.link/api/h/atlas/message/${messageId}`);

    if (!response.ok) {
      console.error(`Error fetching CCIP data: ${response.status} ${response.statusText}`);
      return res.status(response.status).json({
        error: `Error fetching CCIP data: ${response.status} ${response.statusText}`
      });
    }

    const data = await response.json();
    console.log('CCIP data received successfully');
    return res.json(data);
  } catch (error) {
    console.error('Error fetching CCIP message data:', error);
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