import React, { createContext, useContext, useState, useEffect } from 'react';
import { Hex } from 'viem';

// Define the structure for a CCIP transaction
export interface CCIPTransaction {
  txHash: string;
  messageId: string;
  timestamp: number; // Unix timestamp
  type: 'deposit' | 'withdrawal' | 'completeWithdrawal' | 'other';
  status: 'pending' | 'confirmed' | 'failed';
  from: string;
  to: string; // target contract
}

interface TransactionHistoryContextType {
  transactions: CCIPTransaction[];
  addTransaction: (transaction: CCIPTransaction) => void;
  updateTransaction: (messageId: string, updates: Partial<CCIPTransaction>) => void;
  updateTransactionByHash: (txHash: string, updates: Partial<CCIPTransaction>) => void;
  clearHistory: () => void;
}

const TransactionHistoryContext = createContext<TransactionHistoryContextType | null>(null);

// LocalStorage key for storing transaction history
const STORAGE_KEY = 'ccip_transaction_history';

export const TransactionHistoryProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [transactions, setTransactions] = useState<CCIPTransaction[]>([]);

  // Load transaction history from localStorage on component mount
  useEffect(() => {
    const storedTransactions = localStorage.getItem(STORAGE_KEY);
    if (storedTransactions) {
      try {
        setTransactions(JSON.parse(storedTransactions));
      } catch (error) {
        console.error('Failed to parse stored transaction history:', error);
        // If parsing fails, just start with an empty array
        setTransactions([]);
      }
    }
  }, []);

  // Save transaction history to localStorage whenever it changes
  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(transactions));
  }, [transactions]);

  // Add a new transaction to the history
  const addTransaction = (transaction: CCIPTransaction) => {
    setTransactions(prevTransactions => {
      // Check if transaction already exists
      const existingIndex = prevTransactions.findIndex(tx => tx.txHash === transaction.txHash);

      if (existingIndex >= 0) {
        // Replace the existing transaction with the updated one
        const newTransactions = [...prevTransactions];

        // If the new transaction has a messageId and the old one doesn't, use the new messageId
        // Otherwise retain other fields and only update what's changed
        newTransactions[existingIndex] = {
          ...prevTransactions[existingIndex],
          ...transaction,
          // Use the new messageId if it exists, otherwise keep the old one
          messageId: transaction.messageId || prevTransactions[existingIndex].messageId,
          // Update status if needed
          status: transaction.status || prevTransactions[existingIndex].status
        };

        console.log("Updated existing transaction:", newTransactions[existingIndex]);
        return newTransactions;
      }

      // Add new transaction at the beginning of the array (newest first)
      console.log("Adding new transaction:", transaction);
      return [transaction, ...prevTransactions];
    });
  };

  // Update an existing transaction by messageId
  const updateTransaction = (messageId: string, updates: Partial<CCIPTransaction>) => {
    setTransactions(prevTransactions =>
      prevTransactions.map(tx =>
        tx.messageId === messageId ? { ...tx, ...updates } : tx
      )
    );
  };

  // Update an existing transaction by transaction hash
  const updateTransactionByHash = (txHash: string, updates: Partial<CCIPTransaction>) => {
    setTransactions(prevTransactions =>
      prevTransactions.map(tx =>
        tx.txHash === txHash ? { ...tx, ...updates } : tx
      )
    );
  };

  // Clear transaction history
  const clearHistory = () => {
    setTransactions([]);
    localStorage.removeItem(STORAGE_KEY);
  };

  return (
    <TransactionHistoryContext.Provider value={{
      transactions,
      addTransaction,
      updateTransaction,
      updateTransactionByHash,
      clearHistory
    }}>
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