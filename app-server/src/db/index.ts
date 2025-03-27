import Database from 'better-sqlite3';
import path from 'path';
import { fileURLToPath } from 'url';
import { ErrorResponse } from '../types';
import { ETH_CHAINID, L2_CHAINID } from '../utils/constants';

// Get the directory name
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Use in-memory database for tests
const dbPath = process.env.NODE_ENV === 'test'
  ? ':memory:'
  : process.env.DATABASE_PATH || path.join(__dirname, '..', '..', 'data', 'transactions.db');

console.log(`Database path: ${dbPath}`);

// Create or open the database
const db = new Database(dbPath);

export type TransactionTypes =
  | 'deposit'
  | 'queueWithdrawal'
  | 'completeWithdrawal'
  | 'processClaim'
  | 'bridgingWithdrawalToL2'
  | 'bridgingRewardsToL2'
  | 'delegateTo'
  | 'undelegate'
  | 'redelegate';

// Define transaction interface (matches CCIPTransaction in server.ts)
export interface Transaction {
  txHash: string;
  messageId: string;
  timestamp: number;
  txType: TransactionTypes;
  status: 'pending' | 'confirmed' | 'failed';
  from: string;
  to: string;
  receiptTransactionHash: string | null;
  isComplete: boolean;
  sourceChainId: string | number;
  destinationChainId: string | number;
  user: string;
  execNonce: number | null;
}

// Define a type for the database row (column names match SQLite schema)
type TransactionRow = {
  txHash: string;
  messageId: string;
  timestamp: number;
  txType: TransactionTypes;
  status: 'pending' | 'confirmed' | 'failed';
  from_address: string;
  to_address: string;
  receiptTransactionHash: string | null;
  isComplete: number; // SQLite stores booleans as 0/1
  sourceChainId: string;
  destinationChainId: string;
  user: string;
  execNonce: number | null;
};

// Initialize the database with necessary tables
export function initDatabase() {
  try {
    // Create transactions table if it doesn't exist
    db.prepare(`
      CREATE TABLE IF NOT EXISTS transactions (
        txHash TEXT PRIMARY KEY,
        messageId TEXT,
        timestamp INTEGER,
        txType TEXT CHECK(txType IN ('deposit', 'queueWithdrawal', 'completeWithdrawal', 'processClaim', 'bridgingWithdrawalToL2', 'bridgingRewardsToL2', 'delegateTo', 'undelegate', 'redelegate')),
        status TEXT CHECK(status IN ('pending', 'confirmed', 'failed')),
        from_address TEXT,
        to_address TEXT,
        receiptTransactionHash TEXT,
        isComplete INTEGER CHECK(isComplete IN (0, 1)),
        sourceChainId TEXT,
        destinationChainId TEXT,
        user TEXT,
        UNIQUE(messageId)
      )
    `).run();

    // Create indexes for common query patterns
    db.prepare('CREATE INDEX IF NOT EXISTS idx_message_id ON transactions(messageId)').run();
    db.prepare('CREATE INDEX IF NOT EXISTS idx_user ON transactions(user)').run();
    db.prepare('CREATE INDEX IF NOT EXISTS idx_receipt_tx_hash ON transactions(receiptTransactionHash)').run();

    // Check if we need to add the execNonce column
    let hasExecNonceColumn = false;
    try {
      // Try to get table info to check if execNonce column exists
      const tableInfo = db.prepare("PRAGMA table_info(transactions)").all();
      hasExecNonceColumn = tableInfo.some((column: any) => column.name === 'execNonce');

      if (!hasExecNonceColumn) {
        console.log('Adding execNonce column to transactions table...');
        db.prepare('ALTER TABLE transactions ADD COLUMN execNonce INTEGER').run();

        // After adding the column, set NULL for all existing transactions
        db.prepare('UPDATE transactions SET execNonce = NULL').run();

        console.log('execNonce column added successfully');

        // Create index for the new column
        db.prepare('CREATE INDEX IF NOT EXISTS idx_eigen_agent_exec_nonce ON transactions(user, execNonce)').run();
      } else {
        // Create index if the column already exists but index might not
        db.prepare('CREATE INDEX IF NOT EXISTS idx_eigen_agent_exec_nonce ON transactions(user, execNonce)').run();
      }
    } catch (error) {
      console.error('Error checking or adding execNonce column:', error);
      throw error;
    }

    // Check if the table needs to be migrated (if it already exists but with old schema)
    try {
      // Attempt to insert a test transaction with 'processClaim' type
      // If it fails due to constraint, we need to migrate
      const testTxHash = 'test_' + Date.now();
      db.prepare(`
        INSERT INTO transactions (
          txHash, messageId, timestamp, txType, status,
          from_address, to_address, receiptTransactionHash,
          isComplete, sourceChainId, destinationChainId, user
        ) VALUES (
          ?, ?, ?, 'processClaim', 'pending',
          '0x', '0x', NULL,
          0, ?, ?, '0x'
        )
      `).run(testTxHash, testTxHash, Date.now(), ETH_CHAINID, ETH_CHAINID);

      // If we get here, the constraint check passed, so delete the test transaction
      db.prepare('DELETE FROM transactions WHERE txHash = ?').run(testTxHash);
    } catch (error) {
      const errorResponse = error as ErrorResponse;
      // If there's a constraint error, the table needs to be migrated
      if (errorResponse.code === 'SQLITE_CONSTRAINT_CHECK') {
        console.log('Migrating database schema to support processClaim transaction type...');

        // SQLite doesn't support direct ALTER TABLE for modifying constraints
        // We need to rename the old table, create a new one with the updated schema,
        // copy the data, then drop the old table

        // 1. Rename the existing table
        db.prepare('ALTER TABLE transactions RENAME TO transactions_old').run();

        // 2. Create new table with updated schema
        db.prepare(`
          CREATE TABLE transactions (
            txHash TEXT PRIMARY KEY,
            messageId TEXT,
            timestamp INTEGER,
            txType TEXT CHECK(txType IN ('deposit', 'queueWithdrawal', 'completeWithdrawal', 'processClaim', 'bridgingWithdrawalToL2', 'bridgingRewardsToL2', 'delegateTo', 'undelegate', 'redelegate')),
            status TEXT CHECK(status IN ('pending', 'confirmed', 'failed')),
            from_address TEXT,
            to_address TEXT,
            receiptTransactionHash TEXT,
            isComplete INTEGER CHECK(isComplete IN (0, 1)),
            sourceChainId TEXT,
            destinationChainId TEXT,
            user TEXT,
            execNonce INTEGER,
            UNIQUE(messageId)
          )
        `).run();

        // 3. Copy data from old table to new table
        db.prepare(`
          INSERT INTO transactions
          SELECT * FROM transactions_old
        `).run();

        // 4. Recreate indexes
        db.prepare('CREATE INDEX IF NOT EXISTS idx_message_id ON transactions(messageId)').run();
        db.prepare('CREATE INDEX IF NOT EXISTS idx_user ON transactions(user)').run();
        db.prepare('CREATE INDEX IF NOT EXISTS idx_receipt_tx_hash ON transactions(receiptTransactionHash)').run();
        db.prepare('CREATE INDEX IF NOT EXISTS idx_eigen_agent_exec_nonce ON transactions(user, execNonce)').run();

        // 5. Drop old table
        db.prepare('DROP TABLE transactions_old').run();

        console.log('Database schema successfully migrated');
      } else {
        // If it's not a constraint error, re-throw it
        throw error;
      }
    }

    console.log('Database initialized successfully');
  } catch (error) {
    console.error('Error initializing database:', error);
    throw error;
  }
}

// Helper function to convert a database row to a Transaction object
function rowToTransaction(row: TransactionRow): Transaction {
  return {
    txHash: row.txHash,
    messageId: row.messageId,
    timestamp: row.timestamp,
    txType: row.txType,
    status: row.status,
    from: row.from_address,
    to: row.to_address,
    receiptTransactionHash: row.receiptTransactionHash,
    isComplete: Boolean(row.isComplete),
    sourceChainId: row.sourceChainId,
    destinationChainId: row.destinationChainId,
    user: row.user,
    execNonce: row.execNonce
  };
}

// Add a new transaction
export function addTransaction(transaction: Transaction): Transaction {
  // Ensure all required fields have values
  const safeTransaction = {
    ...transaction,
    messageId: transaction.messageId || transaction.txHash,
    timestamp: transaction.timestamp || Math.floor(Date.now() / 1000),
    txType: transaction.txType || 'other',
    status: transaction.status || 'pending',
    from: transaction.from || '0x0000000000000000000000000000000000000000',
    to: transaction.to || '0x0000000000000000000000000000000000000000',
    receiptTransactionHash: transaction.receiptTransactionHash || null,
    isComplete: transaction.isComplete === undefined ? false : transaction.isComplete,
    sourceChainId: transaction.sourceChainId || ETH_CHAINID, // Default to Sepolia
    destinationChainId: transaction.destinationChainId || ETH_CHAINID, // Default to Sepolia
    user: transaction.user || transaction.from || '0x0000000000000000000000000000000000000000',
    execNonce: transaction.execNonce || null
  };

  const stmt = db.prepare(`
    INSERT OR REPLACE INTO transactions (
      txHash, messageId, timestamp, txType, status,
      from_address, to_address, receiptTransactionHash,
      isComplete, sourceChainId, destinationChainId, user, execNonce
    ) VALUES (
      @txHash, @messageId, @timestamp, @txType, @status,
      @from, @to, @receiptTransactionHash,
      @isComplete, @sourceChainId, @destinationChainId, @user, @execNonce
    )
  `);

  // Run the statement with the transaction data
  const result = stmt.run({
    txHash: safeTransaction.txHash,
    messageId: safeTransaction.messageId,
    timestamp: safeTransaction.timestamp,
    txType: safeTransaction.txType,
    status: safeTransaction.status,
    from: safeTransaction.from,
    to: safeTransaction.to,
    receiptTransactionHash: safeTransaction.receiptTransactionHash || null,
    isComplete: safeTransaction.isComplete ? 1 : 0,
    sourceChainId: safeTransaction.sourceChainId.toString(),
    destinationChainId: safeTransaction.destinationChainId.toString(),
    user: safeTransaction.user,
    execNonce: safeTransaction.execNonce || null
  });

  return safeTransaction;
}

// Get all transactions
export function getAllTransactions(): Transaction[] {
  const rows = db.prepare(`
    SELECT
      txHash, messageId, timestamp, txType, status,
      from_address, to_address, receiptTransactionHash,
      isComplete, sourceChainId, destinationChainId, user, execNonce
    FROM transactions
    ORDER BY timestamp DESC
  `).all() as TransactionRow[];

  // Convert rows to Transaction objects
  return rows.map(row => rowToTransaction(row));
}

// Get a transaction by hash
export function getTransactionByHash(txHash: string): Transaction | undefined {
  const row = db.prepare(`
    SELECT
      txHash, messageId, timestamp, txType, status,
      from_address, to_address, receiptTransactionHash,
      isComplete, sourceChainId, destinationChainId, user, execNonce
    FROM transactions
    WHERE txHash = ?
  `).get(txHash) as TransactionRow | undefined;

  if (!row) return undefined;

  return rowToTransaction(row);
}

// Get a transaction by messageId
export function getTransactionByMessageId(messageId: string): Transaction | undefined {
  const row = db.prepare(`
    SELECT
      txHash, messageId, timestamp, txType, status,
      from_address, to_address, receiptTransactionHash,
      isComplete, sourceChainId, destinationChainId, user, execNonce
    FROM transactions
    WHERE messageId = ?
  `).get(messageId) as TransactionRow | undefined;

  if (!row) return undefined;

  return rowToTransaction(row);
}

// Get transactions by user address
export function getTransactionsByUser(userAddress: string): Transaction[] {
  const rows = db.prepare(`
    SELECT
      txHash, messageId, timestamp, txType, status,
      from_address, to_address, receiptTransactionHash,
      isComplete, sourceChainId, destinationChainId, user, execNonce
    FROM transactions
    WHERE user = ?
    ORDER BY timestamp DESC
  `).all(userAddress) as TransactionRow[];

  return rows.map(row => rowToTransaction(row));
}

// Update a transaction
export function updateTransaction(txHash: string, updates: Partial<Transaction>): Transaction | undefined {
  // Get the current transaction
  const currentTx = getTransactionByHash(txHash);
  if (!currentTx) return undefined;

  // Create the updated transaction
  const updatedTx = { ...currentTx, ...updates };

  // Create the update statement
  const stmt = db.prepare(`
    UPDATE transactions SET
      messageId = @messageId,
      timestamp = @timestamp,
      txType = @txType,
      status = @status,
      from_address = @from,
      to_address = @to,
      receiptTransactionHash = @receiptTransactionHash,
      isComplete = @isComplete,
      sourceChainId = @sourceChainId,
      destinationChainId = @destinationChainId,
      user = @user,
      execNonce = @execNonce
    WHERE txHash = @txHash
  `);

  // Run the update
  stmt.run({
    txHash: updatedTx.txHash,
    messageId: updatedTx.messageId,
    timestamp: updatedTx.timestamp,
    txType: updatedTx.txType,
    status: updatedTx.status,
    from: updatedTx.from,
    to: updatedTx.to,
    receiptTransactionHash: updatedTx.receiptTransactionHash || null,
    isComplete: updatedTx.isComplete ? 1 : 0,
    sourceChainId: updatedTx.sourceChainId.toString(),
    destinationChainId: updatedTx.destinationChainId.toString(),
    user: updatedTx.user,
    execNonce: updatedTx.execNonce || null
  });

  return updatedTx;
}

// Update a transaction by messageId
export function updateTransactionByMessageId(messageId: string, updates: Partial<Transaction>): Transaction | undefined {
  // Get the current transaction
  const currentTx = getTransactionByMessageId(messageId);
  if (!currentTx) return undefined;

  return updateTransaction(currentTx.txHash, updates);
}

// Get all pending (incomplete) transactions
export function getPendingTransactions(): Transaction[] {
  const rows = db.prepare(`
    SELECT
      txHash, messageId, timestamp, txType, status,
      from_address, to_address, receiptTransactionHash,
      isComplete, sourceChainId, destinationChainId, user, execNonce
    FROM transactions
    WHERE isComplete = 0
    ORDER BY timestamp DESC
  `).all() as TransactionRow[];

  return rows.map(row => rowToTransaction(row));
}

// Get the most recent execNonce for an EigenAgent (user address)
export function getLatestExecNonceForAgent(agentAddress: string): number | null {
  // First, check for pending transactions for this agent with the highest execNonce
  const pendingRow = db.prepare(`
    SELECT MAX(execNonce) as latestNonce
    FROM transactions
    WHERE user = ? AND isComplete = 0 AND execNonce IS NOT NULL
  `).get(agentAddress) as { latestNonce: number | null } | undefined;

  if (pendingRow?.latestNonce) {
    return pendingRow.latestNonce;
  }

  // If no pending transactions, get the most recent completed transaction's execNonce
  const completedRow = db.prepare(`
    SELECT MAX(execNonce) as latestNonce
    FROM transactions
    WHERE user = ? AND execNonce IS NOT NULL
    ORDER BY timestamp DESC
  `).get(agentAddress) as { latestNonce: number | null } | undefined;

  return completedRow?.latestNonce || null;
}

// Clear all transactions from the database
export function clearTransactions(): void {
  db.prepare('DELETE FROM transactions').run();
  console.log('All transactions cleared from the database');
}

// Add multiple transactions at once
export function addTransactions(transactions: Transaction[]): Transaction[] {
  const stmt = db.prepare(`
    INSERT OR REPLACE INTO transactions (
      txHash, messageId, timestamp, txType, status,
      from_address, to_address, receiptTransactionHash,
      isComplete, sourceChainId, destinationChainId, user, execNonce
    ) VALUES (
      @txHash, @messageId, @timestamp, @txType, @status,
      @from, @to, @receiptTransactionHash,
      @isComplete, @sourceChainId, @destinationChainId, @user, @execNonce
    )
  `);

  // Start a transaction for better performance
  const dbTransaction = db.transaction((txs: Transaction[]) => {
    for (const tx of txs) {
      // Assign default values for missing chain IDs based on transaction type
      let sourceChain = tx.sourceChainId;
      let destChain = tx.destinationChainId;

      // If chain IDs are missing, set defaults based on transaction type
      if (!sourceChain || !destChain) {
        if (tx.txType === 'bridgingWithdrawalToL2' || tx.txType === 'bridgingRewardsToL2') {
          // Default for L1->L2 transactions
          sourceChain = sourceChain || ETH_CHAINID; // Sepolia
          destChain = destChain || L2_CHAINID;      // Base Sepolia
        } else if (tx.txType === 'deposit') {
          // Default for L2->L1 transactions
          sourceChain = sourceChain || L2_CHAINID;   // Base Sepolia
          destChain = destChain || ETH_CHAINID;      // Sepolia
        } else {
          // Default for other transactions
          sourceChain = sourceChain || ETH_CHAINID;  // Default to Sepolia
          destChain = destChain || ETH_CHAINID;      // Default to Sepolia
        }
      }

      stmt.run({
        txHash: tx.txHash,
        messageId: tx.messageId || tx.txHash, // Use txHash as fallback for messageId
        timestamp: tx.timestamp,
        txType: tx.txType,
        status: tx.status,
        from: tx.from,
        to: tx.to,
        receiptTransactionHash: tx.receiptTransactionHash || null,
        isComplete: tx.isComplete ? 1 : 0,
        sourceChainId: String(sourceChain),
        destinationChainId: String(destChain),
        user: tx.user,
        execNonce: tx.execNonce || null
      });
    }
    return txs;
  });

  // Execute the transaction
  return dbTransaction(transactions);
}

// Initialize the database on module import
initDatabase();

// Export the database for direct access if needed
export { db };