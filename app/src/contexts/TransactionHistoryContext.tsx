import React, { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react';
import { useClientsContext } from './ClientsContext';
import { CCIPTransaction, SERVER_BASE_URL, TransactionTypes } from '../utils/ccipEventListener';


interface TransactionHistoryContextType {
  transactions: CCIPTransaction[];
  isLoading: boolean;
  error: string | null;
  fetchTransactions: () => Promise<void>;
  addTransaction: (transaction: CCIPTransaction) => Promise<void>;
  fetchCCIPMessageDetails: (messageId: string) => Promise<any>;
}

const TransactionHistoryContext = createContext<TransactionHistoryContextType | null>(null);

export const TransactionHistoryProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [transactions, setTransactions] = useState<CCIPTransaction[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const { l2Wallet, l1Wallet } = useClientsContext();

  // Refs for transaction polling
  const intervalRef = useRef<NodeJS.Timeout | null>(null);
  const isPollingRef = useRef(false);

  // Function to fetch all transactions from the server
  const fetchTransactions = async () => {
    setIsLoading(true);
    setError(null);

    // Set a timeout to abort the request if it takes too long
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 10000);

    try {
      // Use user-specific endpoint if wallet is connected
      const endpoint = l1Wallet.account
        ? `${SERVER_BASE_URL}/api/transactions/user/${l1Wallet.account}`
        : `${SERVER_BASE_URL}/api/transactions`;

      console.log(`Fetching transactions from ${endpoint}`);

      const response = await fetch(endpoint, {
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

  // Function to start polling for transaction updates
  const startPolling = useCallback(() => {
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
  }, []);

  // Function to stop polling
  const stopPolling = useCallback(() => {
    console.log('Stopping transaction polling');

    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }

    isPollingRef.current = false;
  }, []);

  // Start/stop polling based on l2Wallet.publicClient availability
  useEffect(() => {
    if (l2Wallet.publicClient) {
      console.log('L2 wallet client detected, starting transaction history polling...');
      startPolling();

      return () => {
        console.log('Stopping transaction history polling...');
        stopPolling();
      };
    }
  }, [l2Wallet.publicClient, startPolling, stopPolling]);

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

  // Fetch transaction history from server on component mount
  useEffect(() => {
    fetchTransactions();
  }, []);

  // Add a new transaction to the history
  const addTransaction = async (transaction: CCIPTransaction) => {
    setIsLoading(true);
    setError(null);

    try {
      // Ensure all required fields are present, including CCIP-related data
      const confirmedTransaction: CCIPTransaction = {
        ...transaction,
        status: 'confirmed',
        receiptTransactionHash: transaction.receiptTransactionHash,
        isComplete: transaction.isComplete || false,
        sourceChainId: transaction.sourceChainId,
        destinationChainId: transaction.destinationChainId
      };

      console.log("Adding transaction:", confirmedTransaction);
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