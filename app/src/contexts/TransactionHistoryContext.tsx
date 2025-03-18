import React, { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react';

// Define the structure for a CCIP transaction
export interface CCIPTransaction {
  txHash: string;
  messageId: string;
  timestamp: number; // Unix timestamp
  type: 'deposit' | 'withdrawal' | 'completeWithdrawal' | 'processClaim' | 'bridgingWithdrawalToL2' | 'bridgingRewardsToL2' | 'other';
  status: 'pending' | 'confirmed' | 'failed';
  from: string;
  to: string; // target contract
  receiptTransactionHash?: string; // Optional field for tracking the receipt transaction hash for CCIP messages
  isComplete?: boolean; // Optional field for tracking the completion status of bridgingWithdrawalToL2 transactions
  sourceChainId?: string | number;
  destinationChainId?: string | number;
  user: string;
}

// Define server base URL
const SERVER_BASE_URL = 'http://localhost:3001';

export type TransactionTypes =
  | 'deposit'
  | 'withdrawal'
  | 'completeWithdrawal'
  | 'claim'
  | 'depositToL2'
  | 'bridgingWithdrawalToL2'
  | 'bridgingRewardsToL2';

interface TransactionHistoryContextType {
  transactions: CCIPTransaction[];
  isLoading: boolean;
  error: string | null;
  fetchTransactions: () => Promise<void>;
  addTransaction: (transaction: CCIPTransaction) => Promise<void>;
  updateTransaction: (messageId: string, updates: Partial<CCIPTransaction>) => Promise<void>;
  clearHistory: () => Promise<void>;
  fetchCCIPMessageDetails: (messageId: string) => Promise<any>;
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
    // Don't set loading to true if already loading (prevents multiple concurrent requests)
    if (isLoading) {
      console.log('Already fetching transactions, skipping');
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      console.log('Fetching transactions from server');
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 10000); // 10-second timeout

      const response = await fetch(`${SERVER_BASE_URL}/api/transactions`, {
        signal: controller.signal
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        throw new Error(`Failed to fetch transactions: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      setTransactions(data);
    } catch (err: any) {
      console.error('Error fetching transactions:', err);
      setError(err.message || 'Failed to fetch transactions');
    } finally {
      setIsLoading(false);
    }
  };

  // Add a new transaction to the history
  const addTransaction = async (transaction: CCIPTransaction) => {
    setIsLoading(true);
    setError(null);

    try {
      // Ensure all required fields are present, including CCIP-related data
      const confirmedTransaction: CCIPTransaction = {
        ...transaction,
        status: 'confirmed',
        // Make sure these fields are included even if undefined to ensure consistency
        receiptTransactionHash: transaction.receiptTransactionHash,
        isComplete: transaction.isComplete || false,
        sourceChainId: transaction.sourceChainId,
        destinationChainId: transaction.destinationChainId
      };

      const response = await fetch(`${SERVER_BASE_URL}/api/transactions/add`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(confirmedTransaction),
      });

      if (!response.ok) {
        throw new Error(`Failed to add transaction: ${response.status} ${response.statusText}`);
      }

      // Update local state
      setTransactions(prevTransactions => {
        // Check if transaction already exists
        const existingIndex = prevTransactions.findIndex(tx => tx.txHash === transaction.txHash);
        let newTransactions: CCIPTransaction[];

        if (existingIndex >= 0) {
          // Replace the existing transaction with the updated one
          newTransactions = [...prevTransactions];
          newTransactions[existingIndex] = {
            ...prevTransactions[existingIndex],
            ...confirmedTransaction,
            messageId: confirmedTransaction.messageId || prevTransactions[existingIndex].messageId
          };
        } else {
          // Add new transaction at the beginning of the array (newest first)
          newTransactions = [confirmedTransaction, ...prevTransactions];
        }

        return newTransactions;
      });
    } catch (err: any) {
      console.error('Error adding transaction:', err);
      setError(err.message || 'Failed to add transaction');
    } finally {
      setIsLoading(false);
    }
  };

  // Update an existing transaction by messageId
  const updateTransaction = async (messageId: string, updates: Partial<CCIPTransaction>) => {
    setIsLoading(true);
    setError(null);

    try {
      // Ensure the updates include all necessary fields
      const completeUpdates = {
        ...updates,
        // If the transaction is being marked as complete, ensure these fields are set properly
        ...(updates.status === 'confirmed' && {
          isComplete: updates.isComplete !== undefined ? updates.isComplete : true,
        }),
      };

      const response = await fetch(`${SERVER_BASE_URL}/api/transactions/messageId/${messageId}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(completeUpdates),
      });

      if (!response.ok) {
        throw new Error(`Failed to update transaction: ${response.status} ${response.statusText}`);
      }

      // Update local state
      setTransactions(prevTransactions => {
        const updatedTransactions = prevTransactions.map(tx =>
          tx.messageId === messageId ? { ...tx, ...completeUpdates } : tx
        );

        return updatedTransactions;
      });
    } catch (err: any) {
      console.error('Error updating transaction:', err);
      setError(err.message || 'Failed to update transaction');

      // Update local state even if server request fails
      setTransactions(prevTransactions => {
        const updatedTransactions = prevTransactions.map(tx =>
          tx.messageId === messageId ? { ...tx, ...updates } : tx
        );

        return updatedTransactions;
      });
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
    } catch (err: any) {
      console.error('Error clearing transaction history:', err);
      setError(err.message || 'Failed to clear transaction history');

      // Clear local state even if server request fails
      setTransactions([]);
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

  return (
    <TransactionHistoryContext.Provider
      value={{
        transactions,
        isLoading,
        error,
        fetchTransactions,
        addTransaction,
        updateTransaction,
        clearHistory,
        fetchCCIPMessageDetails,
      }}
    >
      {children}
    </TransactionHistoryContext.Provider>
  );
};

// Custom hook to use the transaction history context
export const useTransactionHistory = (): TransactionHistoryContextType => {
  const context = useContext(TransactionHistoryContext);
  if (!context) {
    throw new Error('useTransactionHistory must be used within a TransactionHistoryProvider');
  }
  return context;
};

// Custom hook for polling transaction history at regular intervals
export const useTransactionHistoryPolling = () => {
  const { fetchTransactions } = useTransactionHistory();
  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const [isPolling, setIsPolling] = useState(false);

  // Use a ref to store stable function references
  const stableCallbacks = useRef({
    startPolling: () => {
      if (isPollingRef.current) return; // Already polling

      console.log('Starting transaction polling');

      // Clear any existing interval first
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }

      // Run once immediately
      fetchTransactions().catch(err => console.error('Error in initial transaction fetch:', err));

      // Set up polling with a reasonable interval (every 2 minutes)
      intervalRef.current = setInterval(() => {
        console.log('Polling for transaction updates...');
        fetchTransactions().catch(err => console.error('Error polling transactions:', err));
      }, 120000); // 2 minutes

      isPollingRef.current = true;
      setIsPolling(true);
    },

    stopPolling: () => {
      console.log('Stopping transaction polling');

      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }

      isPollingRef.current = false;
      setIsPolling(false);
    }
  });

  // Use a ref to track polling state that persists through renders
  const isPollingRef = useRef(false);

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      console.log('Cleaning up transaction polling');
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
      isPollingRef.current = false;
    };
  }, []);

  // Initialize callbacks with access to the current fetchTransactions
  useEffect(() => {
    // Update the fetchTransactions reference in the callbacks
    const originalStartPolling = stableCallbacks.current.startPolling;
    stableCallbacks.current.startPolling = () => {
      if (isPollingRef.current) return; // Already polling

      console.log('Starting transaction polling');

      // Clear any existing interval first
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }

      // Run once immediately
      fetchTransactions().catch(err => console.error('Error in initial transaction fetch:', err));

      // Set up polling with a reasonable interval (every 2 minutes)
      intervalRef.current = setInterval(() => {
        console.log('Polling for transaction updates...');
        fetchTransactions().catch(err => console.error('Error polling transactions:', err));
      }, 120000); // 2 minutes

      isPollingRef.current = true;
      setIsPolling(true);
    };
  }, [fetchTransactions]);

  return stableCallbacks.current;
};