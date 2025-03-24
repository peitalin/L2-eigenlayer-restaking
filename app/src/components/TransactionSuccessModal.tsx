import React from 'react';
import '../styles/modal.css';
import { EthSepolia, BaseSepolia } from '../addresses';
import { EXPLORER_URLS } from '../configs';
import { getCCIPExplorerUrl } from '../utils/ccipEventListener';

interface TransactionSuccessModalProps {
  isOpen: boolean;
  onClose: () => void;
  txHash: string;
  messageId?: string;
  operationType: 'delegate' | 'undelegate' | 'deposit' | 'withdrawal';
  sourceChainId: string;
  destinationChainId: string;
  isLoading?: boolean;
}

const TransactionSuccessModal: React.FC<TransactionSuccessModalProps> = ({
  isOpen,
  onClose,
  txHash,
  messageId,
  operationType,
  sourceChainId,
  destinationChainId,
  isLoading = false
}) => {
  if (!isOpen) return null;

  // Define block explorer URLs based on chain IDs
  const getExplorerUrl = (chainId: string, hash: string) => {
    // Base Sepolia
    if (chainId === BaseSepolia.chainId.toString()) {
      return `${EXPLORER_URLS.basescan}/tx/${hash}`;
    }
    // Ethereum Sepolia
    if (chainId === EthSepolia.chainId.toString()) {
      return `${EXPLORER_URLS.etherscan}/tx/${hash}`;
    }
    return `${EXPLORER_URLS.ccip}/msg/${hash}`;
  };

  // Get CCIP explorer URL for messageId - using imported function
  // const getCCIPExplorerUrl = (messageId: string) => {
  //   return `${EXPLORER_URLS.ccip}/msg/${messageId}`;
  // };

  // Format the title based on operation type
  const getTitle = () => {
    switch (operationType) {
      case 'delegate':
        return isLoading ? 'Delegating...' : 'Successfully Delegated!';
      case 'undelegate':
        return isLoading ? 'Undelegating...' : 'Successfully Undelegated!';
      case 'deposit':
        return isLoading ? 'Depositing...' : 'Successfully Deposited!';
      case 'withdrawal':
        return isLoading ? 'Withdrawing...' : 'Successfully Withdrawn!';
    }
  };

  // Handle close button click - ensure the parent component's onClose gets called
  const handleClose = () => {
    onClose();
  };

  return (
    <div className="modal-overlay" onClick={(e) => {
      // Close when clicking outside the modal
      if (e.target === e.currentTarget) {
        handleClose();
      }
    }}>
      <div className="modal-content">
        <div className="modal-header">
          <h2>{getTitle()}</h2>
          <button className="modal-close" onClick={handleClose}>×</button>
        </div>

        <div className="modal-body">
          <div className={`success-icon ${isLoading ? 'loading' : ''}`}>
            {isLoading ? <div className="loading-spinner"></div> : '✓'}
          </div>

          <div className="transaction-details">
            <p>{isLoading
              ? 'Your transaction is being processed...'
              : 'Your transaction has been submitted and confirmed.'}</p>

            <div className="detail-item">
              <span className="detail-label">Transaction Hash:</span>
              {isLoading ? (
                <span className="detail-value"><div className="loading-spinner small"></div></span>
              ) : (
                <a
                  href={getExplorerUrl(sourceChainId, txHash)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="detail-value link"
                >
                  {txHash.substring(0, 10)}...{txHash.substring(txHash.length - 8)}
                  <span className="external-link-icon">↗</span>
                </a>
              )}
            </div>

            {(messageId || isLoading) && (
              <div className="detail-item">
                <span className="detail-label">CCIP Message ID:</span>
                {isLoading ? (
                  <span className="detail-value"><div className="loading-spinner small"></div></span>
                ) : messageId && messageId !== "" ? (
                  <a
                    href={getCCIPExplorerUrl(messageId)}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="detail-value link"
                  >
                    {messageId.substring(0, 10)}...{messageId.substring(messageId.length - 8)}
                    <span className="external-link-icon">↗</span>
                  </a>
                ) : (
                  <span className="detail-value">Awaiting...</span>
                )}
              </div>
            )}

            <div className="detail-item">
              <span className="detail-label">Status:</span>
              <span className={`detail-value ${isLoading ? 'status-pending' : 'status-success'}`}>
                {isLoading ? 'Processing' : 'Confirmed'}
              </span>
            </div>
          </div>
        </div>

        <div className="modal-footer">
          <button
            className="modal-button"
            onClick={handleClose}
          >
            {"Close"}
          </button>
        </div>
      </div>
    </div>
  );
};

export default TransactionSuccessModal;