import React, { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react';
import { Hex } from 'viem';

// Define the structure for a CCIP transaction
export interface CCIPTransaction {
  txHash: string;
  messageId: string;
  timestamp: number; // Unix timestamp
  type: 'deposit' | 'withdrawal' | 'completeWithdrawal' | 'bridgingWithdrawalToL2' | 'other';
  status: 'pending' | 'confirmed' | 'failed';
  from: string;
  to: string; // target contract
  receiptTransactionHash?: string; // Optional field for tracking the receipt transaction hash for CCIP messages
}

// Define server base URL
const SERVER_BASE_URL = 'http://localhost:3001';

export type TransactionTypes =
  | 'deposit'
  | 'withdrawal'
  | 'completeWithdrawal'
  | 'claim'
  | 'depositToL2'
  | 'bridgingWithdrawalToL2';

interface TransactionHistoryContextType {
  transactions: CCIPTransaction[];
  isLoading: boolean;
  error: string | null;
  fetchTransactions: () => Promise<void>;
  addTransaction: (transaction: CCIPTransaction) => Promise<void>;
  updateTransaction: (messageId: string, updates: Partial<CCIPTransaction>) => Promise<void>;
  updateTransactionByHash: (txHash: string, updates: Partial<CCIPTransaction>) => Promise<void>;
  clearHistory: () => Promise<void>;
  fetchCCIPMessageDetails: (messageId: string) => Promise<any>;
  checkWithdrawalCompletion: (messageId: string, originalTxHash: string) => Promise<boolean>;
}

const TransactionHistoryContext = createContext<TransactionHistoryContextType | null>(null);

export const TransactionHistoryProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [transactions, setTransactions] = useState<CCIPTransaction[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // Fetch transaction history from server on component mount
  useEffect(() => {
    fetchTransactions();
  }, []);

  // Function to fetch all transactions from the server
  const fetchTransactions = async () => {
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch(`${SERVER_BASE_URL}/api/transactions`);

      if (!response.ok) {
        throw new Error(`Failed to fetch transactions: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      setTransactions(data);
    } catch (err: any) {
      console.error('Error fetching transactions:', err);
      setError(err.message || 'Failed to fetch transactions');
      // If server is unavailable, try to use localStorage as fallback
      const storedTransactions = localStorage.getItem('ccip_transaction_history');
    if (storedTransactions) {
      try {
        setTransactions(JSON.parse(storedTransactions));
        } catch (parseErr) {
          console.error('Failed to parse stored transaction history:', parseErr);
      }
    }
    } finally {
      setIsLoading(false);
    }
  };

  // Add a new transaction to the history
  const addTransaction = async (transaction: CCIPTransaction) => {
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch(`${SERVER_BASE_URL}/api/transactions/add`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(transaction),
      });

      if (!response.ok) {
        throw new Error(`Failed to add transaction: ${response.status} ${response.statusText}`);
      }

      // Update local state
    setTransactions(prevTransactions => {
      // Check if transaction already exists
      const existingIndex = prevTransactions.findIndex(tx => tx.txHash === transaction.txHash);

      if (existingIndex >= 0) {
        // Replace the existing transaction with the updated one
        const newTransactions = [...prevTransactions];
        newTransactions[existingIndex] = {
          ...prevTransactions[existingIndex],
          ...transaction,
          messageId: transaction.messageId || prevTransactions[existingIndex].messageId,
          status: transaction.status || prevTransactions[existingIndex].status
        };
        return newTransactions;
      }

      // Add new transaction at the beginning of the array (newest first)
        return [transaction, ...prevTransactions];
      });

      // Also update localStorage as fallback
      localStorage.setItem('ccip_transaction_history', JSON.stringify(transactions));
    } catch (err: any) {
      console.error('Error adding transaction:', err);
      setError(err.message || 'Failed to add transaction');

      // Update local state even if server request fails
      setTransactions(prevTransactions => {
        const existingIndex = prevTransactions.findIndex(tx => tx.txHash === transaction.txHash);
        if (existingIndex >= 0) {
          const newTransactions = [...prevTransactions];
          newTransactions[existingIndex] = {
            ...prevTransactions[existingIndex],
            ...transaction,
            messageId: transaction.messageId || prevTransactions[existingIndex].messageId,
            status: transaction.status || prevTransactions[existingIndex].status
          };
          return newTransactions;
        }
      return [transaction, ...prevTransactions];
    });

      // Update localStorage as fallback
      localStorage.setItem('ccip_transaction_history', JSON.stringify([transaction, ...transactions]));
    } finally {
      setIsLoading(false);
    }
  };

  // Update an existing transaction by messageId
  const updateTransaction = async (messageId: string, updates: Partial<CCIPTransaction>) => {
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch(`${SERVER_BASE_URL}/api/transactions/messageId/${messageId}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(updates),
      });

      if (!response.ok) {
        throw new Error(`Failed to update transaction: ${response.status} ${response.statusText}`);
      }

      // Update local state
      setTransactions(prevTransactions =>
        prevTransactions.map(tx =>
          tx.messageId === messageId ? { ...tx, ...updates } : tx
        )
      );

      // Update localStorage as fallback
      localStorage.setItem('ccip_transaction_history', JSON.stringify(transactions));
    } catch (err: any) {
      console.error('Error updating transaction:', err);
      setError(err.message || 'Failed to update transaction');

      // Update local state even if server request fails
    setTransactions(prevTransactions =>
      prevTransactions.map(tx =>
        tx.messageId === messageId ? { ...tx, ...updates } : tx
      )
    );

      // Update localStorage as fallback
      localStorage.setItem('ccip_transaction_history', JSON.stringify(transactions));
    } finally {
      setIsLoading(false);
    }
  };

  // Update an existing transaction by transaction hash
  const updateTransactionByHash = async (txHash: string, updates: Partial<CCIPTransaction>) => {
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch(`${SERVER_BASE_URL}/api/transactions/${txHash}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(updates),
      });

      if (!response.ok) {
        throw new Error(`Failed to update transaction: ${response.status} ${response.statusText}`);
      }

      // Update local state
      setTransactions(prevTransactions =>
        prevTransactions.map(tx =>
          tx.txHash === txHash ? { ...tx, ...updates } : tx
        )
      );

      // Update localStorage as fallback
      localStorage.setItem('ccip_transaction_history', JSON.stringify(transactions));
    } catch (err: any) {
      console.error('Error updating transaction:', err);
      setError(err.message || 'Failed to update transaction');

      // Update local state even if server request fails
    setTransactions(prevTransactions =>
      prevTransactions.map(tx =>
        tx.txHash === txHash ? { ...tx, ...updates } : tx
      )
    );

      // Update localStorage as fallback
      localStorage.setItem('ccip_transaction_history', JSON.stringify(transactions));
    } finally {
      setIsLoading(false);
    }
  };

  // Clear transaction history
  const clearHistory = async () => {
    setIsLoading(true);
    setError(null);

    try {
      const response = await fetch(`${SERVER_BASE_URL}/api/transactions`, {
        method: 'DELETE',
      });

      if (!response.ok) {
        throw new Error(`Failed to clear transaction history: ${response.status} ${response.statusText}`);
      }

      // Clear local state
      setTransactions([]);
      // Clear localStorage as well
      localStorage.removeItem('ccip_transaction_history');
    } catch (err: any) {
      console.error('Error clearing transaction history:', err);
      setError(err.message || 'Failed to clear transaction history');

      // Clear local state even if server request fails
    setTransactions([]);
      localStorage.removeItem('ccip_transaction_history');
    } finally {
      setIsLoading(false);
    }
  };

  // Fetch CCIP message details
  const fetchCCIPMessageDetails = async (messageId: string) => {
    if (!messageId) {
      return null;
    }

    try {
      const response = await fetch(`${SERVER_BASE_URL}/api/ccip/message/${messageId}`);

      if (!response.ok) {
        throw new Error(`Failed to fetch CCIP message: ${response.status} ${response.statusText}`);
      }

      return await response.json();
    } catch (err: any) {
      console.error(`Error fetching CCIP message ${messageId}:`, err);
      throw new Error(err.message || 'Failed to fetch CCIP message details');
    }
  };

  // New function to check withdrawal completion status
  const checkWithdrawalCompletion = async (messageId: string, originalTxHash: string): Promise<boolean> => {
    try {
      const response = await fetch(`${SERVER_BASE_URL}/api/check-withdrawal-completion`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ messageId, originalTxHash }),
      });

      if (!response.ok) {
        throw new Error(`Server responded with ${response.status}: ${response.statusText}`);
      }

      const data = await response.json();
      console.log('Withdrawal completion check result:', data);

      if (data.isComplete) {
        console.log(`Withdrawal with messageId ${messageId} is complete!`);

        // Update the original transaction
        if (data.updatedOriginalTx) {
          // Make a shallow copy to avoid modifying the response directly
          const updatedTx = {...data.updatedOriginalTx};

          // Update the local transaction
          await updateTransaction(messageId, {
            status: updatedTx.status,
            receiptTransactionHash: updatedTx.receiptTransactionHash
          });
        }

        // Add bridging transaction if it exists
        if (data.bridgingTransaction) {
          await addTransaction(data.bridgingTransaction);
          console.log(`Added bridging transaction with hash: ${data.bridgingTransaction.txHash}`);
        }

        return true;
      }

      return false;
    } catch (error) {
      console.error('Error checking withdrawal completion:', error);
      setError('Failed to check withdrawal completion status');
      throw error;
    }
  };

  return (
    <TransactionHistoryContext.Provider
      value={{
        transactions,
        isLoading,
        error,
        fetchTransactions,
        addTransaction,
        updateTransaction,
        updateTransactionByHash,
        clearHistory,
        fetchCCIPMessageDetails,
        checkWithdrawalCompletion,
      }}
    >
      {children}
    </TransactionHistoryContext.Provider>
  );
};

// Custom hook to use the transaction history context
export const useTransactionHistory = () => {
  const context = useContext(TransactionHistoryContext);
  if (!context) {
    throw new Error('useTransactionHistory must be used within a TransactionHistoryProvider');
  }
  return context;
};

// Add this hook to monitor and process complete withdrawals
export const useCompleteWithdrawalMonitor = (
  checkInterval: number = 60000
): {
  startMonitoring: () => () => void;
  stopMonitoring: () => void;
} => {
  const ctx = useContext(TransactionHistoryContext);

  // Guard against null context
  if (!ctx) {
    throw new Error('useCompleteWithdrawalMonitor must be used within a TransactionHistoryProvider');
  }

  const { transactions, checkWithdrawalCompletion } = ctx;
  const [isMonitoring, setIsMonitoring] = useState(false);
  const timeoutRef = useRef<NodeJS.Timeout | null>(null);

  const monitorWithdrawals = useCallback(() => {
    if (!isMonitoring) return;

    const pendingWithdrawals = transactions.filter(
      (tx) => tx.type === 'completeWithdrawal' && tx.status === 'confirmed' && tx.messageId
    );

    // Process each pending withdrawal
    const processWithdrawals = async () => {
      console.log(`Checking ${pendingWithdrawals.length} pending withdrawals for completion...`);

      for (const withdrawal of pendingWithdrawals) {
        if (withdrawal.messageId && withdrawal.txHash) {
          try {
            await checkWithdrawalCompletion(withdrawal.messageId, withdrawal.txHash);
          } catch (error) {
            console.error(`Error checking withdrawal completion for messageId ${withdrawal.messageId}:`, error);
          }
        }
      }

      // Schedule next check if still monitoring
      if (isMonitoring) {
        timeoutRef.current = setTimeout(monitorWithdrawals, checkInterval);
      }
    };

    processWithdrawals();
  }, [transactions, checkWithdrawalCompletion, isMonitoring, checkInterval]);

  const startMonitoring = useCallback(() => {
    console.log('Starting withdrawal completion monitoring');
    setIsMonitoring(true);

    // Start initial check
    timeoutRef.current = setTimeout(monitorWithdrawals, 0);

    // Return cleanup function
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
        timeoutRef.current = null;
      }
      setIsMonitoring(false);
    };
  }, [monitorWithdrawals]);

  const stopMonitoring = useCallback(() => {
    console.log('Stopping withdrawal completion monitoring');
    setIsMonitoring(false);
    if (timeoutRef.current) {
      clearTimeout(timeoutRef.current);
      timeoutRef.current = null;
    }
  }, []);

  useEffect(() => {
    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
        timeoutRef.current = null;
      }
    };
  }, []);

  return { startMonitoring, stopMonitoring };
};