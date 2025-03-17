import React, { useState, useEffect } from 'react';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { getCCIPExplorerUrl } from '../utils/ccipEventListener';
import { useToast } from './ToastContainer';

interface TransactionHistoryDropdownProps {}

const TransactionHistoryDropdown: React.FC<TransactionHistoryDropdownProps> = () => {
  const { transactions, clearHistory } = useTransactionHistory();
  const [isOpen, setIsOpen] = useState(false);
  const [hasNewTransactions, setHasNewTransactions] = useState(false);
  const [lastViewedCount, setLastViewedCount] = useState(0);
  const { showToast } = useToast();
  const [confirmClearVisible, setConfirmClearVisible] = useState(false);

  // Track when new transactions are added
  useEffect(() => {
    if (transactions.length > lastViewedCount) {
      setHasNewTransactions(true);
    }
  }, [transactions.length, lastViewedCount]);

  // Reset new transaction indicator when opening dropdown
  useEffect(() => {
    if (isOpen) {
      setHasNewTransactions(false);
      setLastViewedCount(transactions.length);
    }
  }, [isOpen, transactions.length]);

  const toggleDropdown = () => {
    setIsOpen(!isOpen);
    // Hide confirm clear if dropdown is being closed
    if (isOpen) {
      setConfirmClearVisible(false);
    }
  };

  const handleClearRequest = (e: React.MouseEvent) => {
    e.stopPropagation();
    setConfirmClearVisible(true);
  };

  const handleConfirmClear = (e: React.MouseEvent) => {
    e.stopPropagation();
    clearHistory();
    setConfirmClearVisible(false);
    showToast('Transaction history cleared', 'info');
  };

  const handleCancelClear = (e: React.MouseEvent) => {
    e.stopPropagation();
    setConfirmClearVisible(false);
  };

  // Helper function to format tx hash or message ID for display
  const formatHash = (hash: string): string => {
    if (!hash) return '';
    return `${hash.substring(0, 6)}...${hash.substring(hash.length - 4)}`;
  };

  // Helper function to format timestamp
  const formatTimestamp = (timestamp: number): string => {
    return new Date(timestamp * 1000).toLocaleString();
  };

  // Helper function to get a label for the transaction type
  const getTransactionTypeLabel = (type: string): string => {
    switch (type) {
      case 'deposit': return 'Deposit';
      case 'withdrawal': return 'Queue Withdrawal';
      case 'completeWithdrawal': return 'Complete Withdrawal';
      default: return 'Transaction';
    }
  };

  // Helper to determine if a messageId is valid
  const isValidMessageId = (messageId: string): boolean => {
    return !!messageId && messageId !== '';
  };

  return (
    <div className="transaction-history-dropdown">
      <button
        onClick={toggleDropdown}
        className={`transaction-history-button ${hasNewTransactions ? 'has-new-transactions' : ''}`}
        title="Transaction History"
      >
        <span>Transactions</span>
        <span className="transaction-count">{transactions.length}</span>
        {hasNewTransactions && <span className="notification-dot"></span>}
      </button>
      {isOpen && (
        <div className="transaction-history-content">
          <div className="transaction-history-header">
            <h3>CCIP Transaction History</h3>
            {!confirmClearVisible ? (
              <button
                onClick={handleClearRequest}
                className="clear-history-button"
                title="Clear History"
              >
                Clear
              </button>
            ) : (
              <div className="confirm-clear-buttons">
                <span className="confirm-text">Are you sure?</span>
                <button
                  onClick={handleConfirmClear}
                  className="confirm-clear-yes"
                  title="Yes, clear history"
                >
                  Yes
                </button>
                <button
                  onClick={handleCancelClear}
                  className="confirm-clear-no"
                  title="No, keep history"
                >
                  No
                </button>
              </div>
            )}
          </div>

          {transactions.length === 0 ? (
            <div className="transaction-history-empty">
              No transactions yet
            </div>
          ) : (
            <div className="transaction-history-list">
              {transactions.map((tx, index) => (
                <div key={index} className="transaction-history-item">
                  <div className="transaction-type">
                    {getTransactionTypeLabel(tx.type)}
                  </div>
                  <div className="transaction-details">
                    <div className="transaction-hash">
                      <span className="transaction-label">Transaction:</span>
                      <a
                        href={`https://sepolia.basescan.org/tx/${tx.txHash}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        title="View on BaseScan"
                      >
                        {formatHash(tx.txHash)}
                      </a>
                    </div>

                    <div className="transaction-ccip">
                      <span className="transaction-label">CCIP Message:</span>
                      {isValidMessageId(tx.messageId) ? (
                        <a
                          href={getCCIPExplorerUrl(tx.messageId)}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="ccip-link"
                          title="View on CCIP Explorer"
                        >
                          {formatHash(tx.messageId)}
                        </a>
                      ) : (
                        <span className="ccip-pending">Pending...</span>
                      )}
                    </div>

                    <div className="transaction-timestamp">
                      {formatTimestamp(tx.timestamp)}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default TransactionHistoryDropdown;