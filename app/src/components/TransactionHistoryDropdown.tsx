import React, { useState, useEffect } from 'react';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { useToast } from '../utils/toast';
import CCIPStatusChecker from './CCIPStatusChecker';

interface TransactionHistoryDropdownProps {}

const TransactionHistoryDropdown: React.FC<TransactionHistoryDropdownProps> = () => {
  const { transactions, isLoading, error } = useTransactionHistory();
  const [isOpen, setIsOpen] = useState(false);
  const [hasNewTransactions, setHasNewTransactions] = useState(false);
  const [lastViewedCount, setLastViewedCount] = useState(0);
  const { showToast } = useToast();

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

  useEffect(() => {
    if (error) {
      showToast(error, 'error');
    }
  }, [error, showToast]);

  const toggleDropdown = () => {
    setIsOpen(!isOpen);
  };

  const formatHash = (hash: string): string => {
    if (!hash) return '';
    return `${hash.substring(0, 6)}...${hash.substring(hash.length - 4)}`;
  };

  const formatTimestamp = (timestamp: number): string => {
    return new Date(timestamp * 1000).toLocaleString();
  };

  const getTransactionTypeLabel = (type: string): string => {
    switch (type) {
      case 'deposit': return 'Deposit';
      case 'bridgingWithdrawalToL2': return 'Bridging Withdrawal to L2';
      case 'bridgingRewardsToL2': return 'Bridging Rewards to L2';
      case 'withdrawal': return 'Queue Withdrawal';
      case 'completeWithdrawal': return 'Complete Withdrawal';
      default: return 'Transaction';
    }
  };

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
          </div>

          {isLoading && transactions.length === 0 ? (
            <div className="transaction-history-loading">
              Loading transactions...
            </div>
          ) : transactions.length === 0 ? (
            <div className="transaction-history-empty">
              No transactions yet
            </div>
          ) : (
            <div className="transaction-history-list">
              {transactions.map((tx, index) => {

                const sourceChain = tx.sourceChainId === "84532" ? 'Base' : 'Ethereum';
                const destinationChain = tx.destinationChainId === "84532" ? 'Base' : 'Ethereum';
                const blockExplorerUrls = {
                  Base: 'https://sepolia.basescan.org/tx/',
                  Ethereum: 'https://sepolia.etherscan.io/tx/',
                };

                return (
                  <div key={index} className="transaction-history-item">
                    <div className="transaction-type">
                      {getTransactionTypeLabel(tx.type)}
                    </div>
                    <div className="transaction-details">
                      <div className="transaction-hash">
                        <span className="transaction-label">{sourceChain}:</span>
                        <a
                          href={`${blockExplorerUrls[sourceChain]}${tx.txHash}`}
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
                          <CCIPStatusChecker
                            messageId={tx.messageId}
                            txType={tx.type}
                          />
                        ) : (
                          <span className="ccip-pending">Pending...</span>
                        )}
                      </div>

                      {
                        tx.receiptTransactionHash &&
                        <div className="receipt-hash">
                          <span className="transaction-label">{destinationChain}:</span>
                          <a
                            href={`${blockExplorerUrls[destinationChain]}${tx.receiptTransactionHash}`}
                            target="_blank"
                            rel="noopener noreferrer"
                          >
                            {`${tx.receiptTransactionHash.substring(0, 10)}...`}
                          </a>
                        </div>
                      }

                      <div className="transaction-timestamp">
                        {formatTimestamp(tx.timestamp)}
                      </div>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default TransactionHistoryDropdown;