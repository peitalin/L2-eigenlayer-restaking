import React, { useState } from 'react';
import { fetchCCIPMessageData, getCCIPMessageStatusText } from '../utils/ccipDataFetcher';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { useToast } from './ToastContainer';
import { getCCIPExplorerUrl } from '../utils/ccipEventListener';

interface CCIPStatusCheckerProps {
  messageId: string;
  txHash?: string;
  showExplorerLink?: boolean;
}

const CCIPStatusChecker: React.FC<CCIPStatusCheckerProps> = ({
  messageId,
  txHash,
  showExplorerLink = true
}) => {
  const [isLoading, setIsLoading] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const { updateTransaction, updateTransactionByHash, fetchCCIPMessageDetails } = useTransactionHistory();
  const { showToast } = useToast();

  const handleCheckStatus = async () => {
    if (!messageId) {
      showToast('No messageId provided', 'error');
      return;
    }

    try {
      setIsLoading(true);

      // Use the function from the context instead of the utility
      const messageData = await fetchCCIPMessageDetails(messageId);

      if (messageData) {
        const statusText = getCCIPMessageStatusText(messageData.state);
        setStatus(statusText);
        showToast(`CCIP Status: ${statusText}`, 'info');

        // Update the transaction in history if we have a txHash or messageId
        if (messageData.state === 2) { // Confirmed
          try {
          if (txHash) {
              await updateTransactionByHash(txHash, { status: 'confirmed' });
          } else {
              await updateTransaction(messageId, { status: 'confirmed' });
            }
          } catch (updateError) {
            console.error('Error updating transaction status:', updateError);
            // Continue without failing the whole operation
          }
        } else if (messageData.state === 3) { // Failed
          try {
          if (txHash) {
              await updateTransactionByHash(txHash, { status: 'failed' });
          } else {
              await updateTransaction(messageId, { status: 'failed' });
            }
          } catch (updateError) {
            console.error('Error updating transaction status:', updateError);
            // Continue without failing the whole operation
          }
        }
      } else {
        showToast('Could not fetch CCIP status', 'error');
      }
    } catch (error) {
      console.error('Error checking CCIP status:', error);
      showToast('Error checking CCIP status', 'error');
    } finally {
      setIsLoading(false);
    }
  };

  const formatMessageId = (id: string): string => {
    if (!id) return '';
    return `${id.substring(0, 6)}...${id.substring(id.length - 4)}`;
  };

  return (
    <div className="ccip-status-checker">
      <div className="ccip-status-container">
        {showExplorerLink && messageId && (
          <a
            href={getCCIPExplorerUrl(messageId)}
            target="_blank"
            rel="noopener noreferrer"
            className="ccip-link"
            title="View on CCIP Explorer"
          >
            {formatMessageId(messageId)}
          </a>
        )}
        <button
          className="ccip-check-button"
          onClick={handleCheckStatus}
          disabled={isLoading || !messageId}
          title="Check CCIP status"
        >
          {isLoading ? '...' : '⟳'}
        </button>
        {status && (
          <span className={`status-badge status-${status.toLowerCase()}`}>
            {status}
          </span>
        )}
      </div>
    </div>
  );
};

export default CCIPStatusChecker;