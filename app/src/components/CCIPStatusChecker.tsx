import React, { useState } from 'react';
import { getCCIPMessageStatusText } from '../utils/ccipEventListener';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { useToast } from '../utils/toast';
import { getCCIPExplorerUrl } from '../utils/ccipEventListener';

interface CCIPStatusCheckerProps {
  messageId: string;
  txType?: string;
  showExplorerLink?: boolean;
}

const CCIPStatusChecker: React.FC<CCIPStatusCheckerProps> = ({
  messageId,
  txType,
  showExplorerLink = true,
}) => {

  const {
    fetchCCIPMessageDetails,
    fetchTransactions,
    updateTransaction
  } = useTransactionHistory();
  const { showToast } = useToast();

  const [isLoading, setIsLoading] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [isConfirmed, setIsConfirmed] = useState(false);
  const [checkingStatus, setCheckingStatus] = useState(false);

  const isWithdrawal = txType === 'completeWithdrawal'
    || txType === 'bridgingWithdrawalToL2'
    || txType === 'bridgingRewardsToL2'
    || txType === 'withdrawal';

  const handleCheckStatus = async () => {
    if (!messageId) {
      showToast('No messageId provided', 'error');
      return;
    }

    try {
      setIsLoading(true);

      // Check CCIP message status
      await checkCCIPStatus();

      // Fetch updated transactions to reflect any server-side updates
      try {
        await fetchTransactions();
      } catch (error) {
        console.error('Error fetching transactions:', error);
      }
    } catch (error) {
      console.error('Error checking status:', error);
      showToast('Error checking status', 'error');
    } finally {
      setIsLoading(false);
    }
  };

  // CCIP status check function
  const checkCCIPStatus = async () => {
    if (!messageId) return;

    setCheckingStatus(true);
    setStatus('Checking...');

    try {
      // Fetch message details from CCIP API via server
      const messageData = await fetchCCIPMessageDetails(messageId);

      if (!messageData) {
        setStatus('Unknown');
        setCheckingStatus(false);
        return;
      }

      // Get status text based on state
      const statusText = getCCIPMessageStatusText(messageData.state);
      setStatus(statusText);

      // Use appropriate toast type based on status
      if (messageData.state === 3) { // Failed
        showToast(`CCIP Status: ${statusText}`, 'error');
      } else {
        showToast(`CCIP Status: ${statusText}`, 'info');
      }

      // Update transaction status in history
      if (messageData.state !== undefined) {
        // Map CCIP state to our transaction status
        let txStatus: 'pending' | 'confirmed' | 'failed';
        let isComplete = false;

        if (messageData.state === 2) { // Confirmed
          txStatus = 'confirmed';
          isComplete = !!messageData.receiptTransactionHash;
        } else if (messageData.state === 3) { // Failed
          txStatus = 'failed';
        } else {
          txStatus = 'pending';
        }

        // Update transaction with CCIP message details
        await updateTransaction(messageId, {
          status: txStatus,
          isComplete,
          receiptTransactionHash: messageData.receiptTransactionHash || undefined,
          sourceChainId: messageData.sourceChainId,
          destinationChainId: messageData.destChainId,
        });

        if (txStatus === 'confirmed') {
          setIsConfirmed(true);
        }
      }

      setCheckingStatus(false);
    } catch (error) {
      console.error('Error checking CCIP message status:', error);
      setStatus('Error');
      showToast(`Error checking CCIP status: ${(error as Error).message}`, 'error');
      setCheckingStatus(false);
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
          title={isWithdrawal ? "Check Withdrawal Status" : "Check CCIP Status"}
        >
          {isLoading ? '...' : '⟳'}
        </button>
      </div>
    </div>
  );
};

export default CCIPStatusChecker;