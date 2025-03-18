import express from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { config } from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { createPublicClient, http, decodeEventLog, PublicClient, keccak256, toBytes } from 'viem';
import { sepolia } from 'viem/chains';
import { parseAbi } from 'viem/utils';

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
  type: 'deposit' | 'withdrawal' | 'completeWithdrawal' | 'bridgingWithdrawalToL2' | 'bridgingRewardsToL2' | 'other';
  status: 'pending' | 'confirmed' | 'failed';
  from: string;
  to: string;
  receiptTransactionHash: string;
  isComplete: boolean;
  sourceChainId: string | number;
  destinationChainId: string | number;
  user: string;
}

// Add this constant for the MessageSent event signature
const MESSAGE_SENT_SIGNATURE = keccak256(toBytes('MessageSent(bytes32 indexed, uint64 indexed, address, (address, uint256)[], address, uint256)'));
// const MESSAGE_SENT_SIGNATURE = '0xf41bc76bbe18ec95334bdb88f45c769b987464044ead28e11193a766ae8225cb';

// Add event signatures for bridging events
const BRIDGING_WITHDRAWAL_TO_L2_SIGNATURE = keccak256(toBytes('BridgingWithdrawalToL2(address,(address,uint256)[])'));
// const BRIDGING_WITHDRAWAL_TO_L2_SIGNATURE = "0xfa108e7e127cd9ffa35e2c8a5e30a502d7bc57f04c0ad2be2018456d8c1704bd"
const BRIDGING_REWARDS_TO_L2_SIGNATURE = keccak256(toBytes('BridgingRewardsToL2(address,(address,uint256)[])'));
// const BRIDGING_REWARDS_TO_L2_SIGNATURE = "0x180f259676103b09549f37ce39504dc86937e3c15825d8172d829f506f7f17b2"
// NOTE: cast sig-event "BridgingRewardsToL2(address,(address,uint256)[])"

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

/**
 * Extract a CCIP messageId and agentOwner from a transaction receipt
 * @param receiptHash Transaction hash to extract data from
 * @param client Viem public client to use for fetching the receipt
 * @returns Object containing messageId and agentOwner if found
 */
const extractMessageIdFromReceipt = async (
  receiptHash: string,
  client: PublicClient
): Promise<{ messageId: string | null, agentOwner: string | null }> => {
  if (!receiptHash || !receiptHash.startsWith('0x')) {
    console.error('Invalid receipt hash provided:', receiptHash);
    return { messageId: null, agentOwner: null };
  }

  try {
    console.log(`Getting transaction receipt for: ${receiptHash}`);
    const hash = receiptHash as `0x${string}`;
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
    console.error(`Error processing transaction receipt for ${receiptHash}:`, error);
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

    // Step 3: Choose the right client based on chainId
    // If chainId is specified, use it to determine which client to use
    let clientToUse: PublicClient = publicClientL1; // Default to L1 client

    if (messageData.destChainId) {
      // Determine which client to use based on chainId
      if (messageData.destChainId === "84532") {
        clientToUse = publicClientL2 as PublicClient;
      } else if (messageData.destChainId === "11155111") {
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
      const transactions: CCIPTransaction[] = JSON.parse(fs.readFileSync(txHistoryPath, 'utf-8'));
      const existingTxIndex = transactions.findIndex(tx => tx.txHash === originalTxHash);

      if (existingTxIndex !== -1) {
        transactions[existingTxIndex] = {
          ...transactions[existingTxIndex],
          ...updatedOriginalTx
        };
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
        transactions.push(bridgingTransaction);
      }

      // 3. Save the updated transaction history
      fs.writeFileSync(txHistoryPath, JSON.stringify(transactions, null, 2));

      // 4. Return the result
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
      to: messageData.receiver || '0x0000000000000000000000000000000000000000',
      receiptTransactionHash: messageData.receiptTransactionHash || txHash,
      isComplete: messageData.receiptTransactionHash ? true : false,
      sourceChainId: messageData.sourceChainId || '11155111',
      destinationChainId: messageData.destChainId || '84532',
      user: messageData.origin || '0x0000000000000000000000000000000000000000',
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

// Periodic task to update pending transactions
async function updatePendingTransactions() {
  console.log('Starting periodic check for pending transactions...');
  try {
    // Read all transactions
    const transactions: CCIPTransaction[] = JSON.parse(fs.readFileSync(txHistoryPath, 'utf-8'));

    // Filter incomplete transactions (pending status or specific transaction types that need completion check)
    const pendingTransactions = transactions.filter(tx => !tx.isComplete);

    if (pendingTransactions.length === 0) {
      console.log('No pending transactions to update');
      return;
    }

    console.log(`Found ${pendingTransactions.length} pending transactions to check`);
    let updatedCount = 0;

    // Check each pending transaction
    for (const tx of pendingTransactions) {
      try {
        let isUpdated = false;

        // For transactions with messageId, check CCIP status
        if (tx.messageId) {
          const messageData = await fetchCCIPMessageData(tx.messageId);

          if (messageData) {
            // Update status based on CCIP message state
            if (messageData.state === 2) { // Confirmed
              tx.status = 'confirmed';
              isUpdated = true;
              console.log(`Updated transaction ${tx.txHash} to confirmed status`);
            } else if (messageData.state === 3) { // Failed
              tx.status = 'failed';
              isUpdated = true;
              console.log(`Updated transaction ${tx.txHash} to failed status`);
            }

            // For bridging transactions, check if the receipt transaction exists
            if ((tx.type === 'bridgingWithdrawalToL2' || tx.type === 'completeWithdrawal' || tx.type === 'bridgingRewardsToL2'
                || tx.type === 'deposit' || tx.type === 'withdrawal')
                && messageData.receiptTransactionHash && !tx.isComplete) {

              // Determine which chain to use based on transaction type
              let client;
              if (tx.type === 'bridgingWithdrawalToL2' || tx.type === 'bridgingRewardsToL2') {
                client = publicClientL2;  // Use L2 client for bridging to L2
              } else if (tx.type === 'deposit' || tx.type === 'withdrawal' || tx.type === 'completeWithdrawal') {
                client = publicClientL1; // Use L1 client for other transaction types
              } else {
                // Determine client based on destination chain
                client = tx.destinationChainId === "84532" ? publicClientL2 : publicClientL1;
              }

              try {
                // Check if the receipt transaction was successful
                const receiptHash = messageData.receiptTransactionHash as `0x${string}`;
                const receipt = await client.getTransactionReceipt({ hash: receiptHash });

                if (receipt && receipt.status === 'success') {
                  tx.isComplete = true;
                  tx.receiptTransactionHash = messageData.receiptTransactionHash;
                  tx.status = 'confirmed';
                  isUpdated = true;
                  console.log(`Completed bridging transaction ${tx.txHash}`);
                }
              } catch (receiptError) {
                console.error(`Error checking receipt transaction for ${tx.txHash}:`, receiptError);
              }
            }
          }
        }

        // Count if we made an update
        if (isUpdated) {
          updatedCount++;
        }
      } catch (txError) {
        console.error(`Error processing transaction ${tx.txHash}:`, txError);
      }
    }

    // Save updated transactions back to file only if we made changes
    if (updatedCount > 0) {
      console.log(`Updated ${updatedCount} transactions, saving to file`);
      fs.writeFileSync(txHistoryPath, JSON.stringify(transactions, null, 2));
    } else {
      console.log('No transaction updates needed');
    }
  } catch (error) {
    console.error('Error updating pending transactions:', error);
  }
}

// Set up periodic task to run every minute
const UPDATE_INTERVAL = 30 * 1000; // 30 seconds
setInterval(updatePendingTransactions, UPDATE_INTERVAL);

// Run an initial update when the server starts
updatePendingTransactions();

// Add this utility function to fix transactions with missing fields
function fixTransactionMissingFields() {
  try {
    console.log('Checking for transactions with missing required fields...');

    // Read all transactions
    const transactions: CCIPTransaction[] = JSON.parse(fs.readFileSync(txHistoryPath, 'utf-8'));
    let modifiedCount = 0;

    // Fix each transaction if needed
    const fixedTransactions = transactions.map(tx => {
      let isModified = false;
      const fixedTx = { ...tx };

      // Add receiptTransactionHash if missing
      if (!fixedTx.receiptTransactionHash) {
        fixedTx.receiptTransactionHash = fixedTx.txHash; // Use txHash as fallback
        isModified = true;
      }

      // Add isComplete if missing
      if (fixedTx.isComplete === undefined) {
        fixedTx.isComplete = fixedTx.status === 'confirmed';
        isModified = true;
      }

      // Add sourceChainId if missing
      if (!fixedTx.sourceChainId) {
        fixedTx.sourceChainId = (fixedTx.type === 'bridgingWithdrawalToL2' || fixedTx.type === 'bridgingRewardsToL2')
          ? '11155111' // Sepolia
          : '84532';   // Base Sepolia
        isModified = true;
      }

      // Add destinationChainId if missing
      if (!fixedTx.destinationChainId) {
        fixedTx.destinationChainId = (fixedTx.type === 'bridgingWithdrawalToL2' || fixedTx.type === 'bridgingRewardsToL2')
          ? '84532'     // Base Sepolia
          : '11155111'; // Sepolia
        isModified = true;
      }

      if (isModified) {
        modifiedCount++;
      }

      return fixedTx;
    });

    // Save fixed transactions back to file only if we made changes
    if (modifiedCount > 0) {
      console.log(`Fixed ${modifiedCount} transactions with missing fields, saving to file`);
      fs.writeFileSync(txHistoryPath, JSON.stringify(fixedTransactions, null, 2));
    } else {
      console.log('No transactions needed fixing');
    }
  } catch (error) {
    console.error('Error fixing transactions with missing fields:', error);
  }
}

// After initializing the server, fix any transactions with missing fields
httpServer.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);

  // Run an initial update when the server starts
  fixTransactionMissingFields();
  updatePendingTransactions();
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