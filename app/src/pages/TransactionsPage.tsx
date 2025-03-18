import React, { useState } from 'react';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import CCIPStatusChecker from '../components/CCIPStatusChecker';
import { useToast } from '../components/ToastContainer';

const TransactionsPage: React.FC = () => {
  const { transactions, clearHistory, isLoading, error } = useTransactionHistory();
  const { showToast } = useToast();
  const [confirmClearVisible, setConfirmClearVisible] = useState(false);
  const [isClearingHistory, setIsClearingHistory] = useState(false);

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

  // Helper to get status badge class
  const getStatusBadgeClass = (status: string): string => {
    switch (status) {
      case 'confirmed':
        return 'status-confirmed';
      case 'failed':
        return 'status-failed';
      case 'pending':
      default:
        return 'status-pending';
    }
  };

  const handleClearRequest = () => {
    setConfirmClearVisible(true);
  };

  const handleConfirmClear = async () => {
    try {
      setIsClearingHistory(true);
      await clearHistory();
      setConfirmClearVisible(false);
      showToast('Transaction history cleared', 'info');
    } catch (err) {
      console.error('Error clearing history:', err);
      showToast('Failed to clear history', 'error');
    } finally {
      setIsClearingHistory(false);
    }
  };

  const handleCancelClear = () => {
    setConfirmClearVisible(false);
  };

  return (
    <div className="transactions-page">
      <div className="transactions-header">
        <h1>Transactions</h1>
        {!confirmClearVisible ? (
          <button
            onClick={handleClearRequest}
            className="clear-history-button"
            title="Clear History"
            disabled={isLoading || isClearingHistory || transactions.length === 0}
          >
            Clear History
          </button>
        ) : (
          <div className="confirm-clear-container">
            <span className="confirm-text">Are you sure?</span>
            <div className="confirm-buttons">
              <button
                onClick={handleConfirmClear}
                className="confirm-clear-yes"
                title="Yes, clear history"
                disabled={isClearingHistory}
              >
                {isClearingHistory ? 'Clearing...' : 'Yes'}
              </button>
              <button
                onClick={handleCancelClear}
                className="confirm-clear-no"
                title="No, keep history"
                disabled={isClearingHistory}
              >
                No
              </button>
            </div>
          </div>
        )}
      </div>

      {isLoading && transactions.length === 0 ? (
        <div className="transactions-loading">
          <div className="loading-spinner"></div>
          <p>Loading transactions...</p>
        </div>
      ) : transactions.length === 0 ? (
        <div className="transactions-empty">
          <p>No transactions yet</p>
          <p className="empty-details">Your transaction history will appear here</p>
        </div>
      ) : (
        <div className="transactions-list">
          <div className="transactions-list-header">
            <div className="transaction-header-type">Type</div>
            <div className="transaction-header-hash">Transaction</div>
            <div className="transaction-header-ccip">CCIP Message</div>
            <div className="transaction-header-time">Time</div>
          </div>
          {transactions.map((tx, index) => (
            <div key={index} className="transaction-item">
              <div className="transaction-type">
                <div className="transaction-type-label">
                  {getTransactionTypeLabel(tx.type)}
                </div>
                <div className={`transaction-status-badge ${getStatusBadgeClass(tx.status)}`}>
                  {tx.status.charAt(0).toUpperCase() + tx.status.slice(1)}
                </div>
              </div>
              <div className="transaction-hash">
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
                {isValidMessageId(tx.messageId) ? (
                  <CCIPStatusChecker
                    messageId={tx.messageId}
                    txHash={tx.txHash}
                  />
                ) : (
                  <span className="ccip-pending">Pending...</span>
                )}
              </div>
              <div className="transaction-timestamp">
                {formatTimestamp(tx.timestamp)}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default TransactionsPage;