import React, { useState, useEffect } from 'react';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import CCIPStatusChecker from '../components/CCIPStatusChecker';
import { useToast } from '../utils/toast';

const TransactionsPage: React.FC = () => {
  const { transactions, isLoading, error } = useTransactionHistory();

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
      case 'queueWithdrawal': return 'Queue Withdrawal';
      case 'completeWithdrawal': return 'Complete Withdrawal';
      case 'processClaim': return 'Rewards Claim';
      case 'bridgingWithdrawalToL2': return 'Bridge Withdrawal to L2';
      case 'bridgingRewardsToL2': return 'Bridge Rewards to L2';
      default: return type.charAt(0).toUpperCase() + type.slice(1);
    }
  };

  // Helper to determine if a messageId is valid
  const isValidMessageId = (messageId: string): boolean => {
    return !!messageId && messageId !== '' && messageId !== '0x';
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

  // Helper to get chain name from chain ID
  const getChainName = (chainId: string | number | undefined): string => {
    if (!chainId) return 'Ethereum'; // Default to Ethereum if undefined
    const id = typeof chainId === 'string' ? chainId : chainId.toString();
    return id === '84532' ? 'Base' : 'Ethereum';
  };

  // Helper to get chain badge class
  const getChainBadgeClass = (chainName: string): string => {
    return `chain-${chainName.toLowerCase()}`;
  };

  return (
    <div className="transaction-form transactions-page">
      <div className="transactions-form-header">
        <h2>Transaction History</h2>
      </div>

      <div className="transactions-form-content">
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
              <div className="table-col col-status">Status</div>
              <div className="table-col col-hash"></div>
              <div className="table-col col-arrow"></div>
              <div className="table-col col-ccip">CCIP Message</div>
              <div className="table-col col-arrow"></div>
              <div className="table-col col-hash"></div>
              <div className="table-col col-time">Time</div>
            </div>
            <div className="transactions-table-body">
              {transactions.map((tx, index) => {

                const sourceChainName = getChainName(tx.sourceChainId);
                const destChainName = getChainName(tx.destinationChainId);
                const blockExplorerUrls: Record<string, string> = {
                  'Base': 'https://sepolia.basescan.org/tx/',
                  'Ethereum': 'https://sepolia.etherscan.io/tx/',
                };

                return (
                  <div key={index} className="transaction-row">
                    <div className="table-col col-type">
                      <div className="transaction-type-label">
                        {getTransactionTypeLabel(tx.txType)}
                      </div>
                    </div>
                    <div className="table-col col-status">
                      <div className={`transaction-status-badge ${getStatusBadgeClass(tx.status)}`}>
                        {tx.status.charAt(0).toUpperCase() + tx.status.slice(1)}
                      </div>
                    </div>
                    <div className="table-col col-hash source-hash">
                      <div className={`source-chain-badge ${getChainBadgeClass(sourceChainName)}`}>
                        {sourceChainName}
                      </div>
                      <a
                        href={`${blockExplorerUrls[sourceChainName] || blockExplorerUrls['Ethereum']}${tx.txHash}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        title={`View on ${sourceChainName}Scan`}
                        className="hash-link"
                      >
                        {formatHash(tx.txHash)}
                      </a>
                    </div>
                    <div className="table-col col-arrow">
                      <span className="directional-arrow">→</span>
                    </div>
                    <div className="table-col col-ccip">
                      {isValidMessageId(tx.messageId) && !!tx.txHash ? (
                        <CCIPStatusChecker
                          messageId={tx.messageId}
                          txType={tx.txType}
                        />
                      ) : (
                        <span className="ccip-pending">
                          {'Pending...'}
                        </span>
                      )}
                    </div>
                    <div className="table-col col-arrow">
                      <span className="directional-arrow">→</span>
                    </div>
                    <div className="table-col col-hash dest-hash">
                      {tx.receiptTransactionHash ? (
                        <>
                          <div className={`source-chain-badge ${getChainBadgeClass(destChainName)}`}>
                            {destChainName}
                          </div>
                          <a
                            href={`${blockExplorerUrls[destChainName] || blockExplorerUrls['Ethereum']}${tx.receiptTransactionHash}`}
                            target="_blank"
                            rel="noopener noreferrer"
                            title={`View on ${destChainName}Scan`}
                            className="hash-link"
                          >
                            {formatHash(tx.receiptTransactionHash)}
                          </a>
                        </>
                        ) : (
                        <>
                          <div className={`source-chain-badge ${getChainBadgeClass(destChainName)}`}>
                            {destChainName}
                          </div>
                          <span className="l1-pending">Pending...</span>
                        </>
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