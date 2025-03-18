import React, { useState, useEffect } from 'react';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import CCIPStatusChecker from '../components/CCIPStatusChecker';
import { useToast } from '../utils/toast';

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
      case 'bridgingWithdrawalToL2': return 'Bridge Withdrawal to L2';
      case 'bridgingRewardsToL2': return 'Bridge Rewards to L2';
      default: return type.charAt(0).toUpperCase() + type.slice(1);
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

  // Helper to determine source chain based on transaction type
  const getSourceChain = (type: string): { chain: string, direction: 'forward' | 'reverse' } => {
    switch (type) {
      case 'deposit':
      case 'withdrawal':
      case 'completeWithdrawal':
        return { chain: 'Base', direction: 'forward' }; // Base Sepolia -> Eth Sepolia
      case 'bridgingWithdrawalToL2':
      case 'bridgingRewardsToL2':
        return { chain: 'Eth', direction: 'reverse' }; // Eth Sepolia -> Base Sepolia
      default:
        return { chain: 'Base', direction: 'forward' };
    }
  };

  // Helper to render directional arrow based on source chain
  const renderDirectionalArrow = (direction: 'forward' | 'reverse'): string => {
    return direction === 'forward' ? '→' : '←';
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
    <div className="transaction-form transactions-page">
      <div className="form-header">
        <h2>Transaction History</h2>
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

      <div className="form-content">
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
          <div className="transactions-table">
            <div className="transactions-table-header">
              <div className="table-col col-type">Type</div>
              <div className="table-col col-source">Source</div>
              <div className="table-col col-status">Status</div>
              <div className="table-col col-hash">L2 Transaction</div>
              <div className="table-col col-ccip">CCIP Message</div>
              <div className="table-col col-l1hash">L1 Transaction</div>
              <div className="table-col col-time">Time</div>
            </div>
            <div className="transactions-table-body">
              {transactions.map((tx, index) => {
                const { chain, direction } = getSourceChain(tx.type);
                const arrow = renderDirectionalArrow(direction);
                return (
                  <div key={index} className="transaction-row">
                    <div className="table-col col-type">
                      <div className="transaction-type-label">
                        {getTransactionTypeLabel(tx.type)}
                      </div>
                    </div>
                    <div className="table-col col-source">
                      <div className={`source-chain-badge chain-${chain.toLowerCase()}`}>
                        {chain}
                      </div>
                    </div>
                    <div className="table-col col-status">
                      <div className={`transaction-status-badge ${getStatusBadgeClass(tx.status)}`}>
                        {tx.status.charAt(0).toUpperCase() + tx.status.slice(1)}
                      </div>
                    </div>
                    <div className="table-col col-hash">
                      <a
                        href={`https://sepolia.basescan.org/tx/${tx.txHash}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        title="View on BaseScan"
                        className="hash-link"
                      >
                        {formatHash(tx.txHash)}
                      </a>
                      <span className="directional-arrow">{arrow}</span>
                    </div>
                    <div className="table-col col-ccip">
                      {isValidMessageId(tx.messageId) ? (
                        <>
                          <CCIPStatusChecker
                            messageId={tx.messageId}
                            txType={tx.type}
                          />
                          <span className="directional-arrow">{arrow}</span>
                        </>
                      ) : (
                        <span className="ccip-pending">Pending...</span>
                      )}
                    </div>
                    <div className="table-col col-l1hash">
                      {tx.receiptTransactionHash ? (
                        <a
                          href={`https://sepolia.etherscan.io/tx/${tx.receiptTransactionHash}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          title="View on Etherscan"
                          className="hash-link"
                        >
                          {formatHash(tx.receiptTransactionHash)}
                        </a>
                      ) : (
                        <span className="l1-pending">Pending...</span>
                      )}
                    </div>
                    <div className="table-col col-time">
                      {formatTimestamp(tx.timestamp)}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default TransactionsPage;