import React, { useEffect, useState } from 'react';
import { CCIPTransaction, useTransactionHistory } from '../contexts/TransactionHistoryContext';

interface WithdrawalCompletionStatusProps {
  transaction: CCIPTransaction;
}

export const WithdrawalCompletionStatus: React.FC<WithdrawalCompletionStatusProps> = ({ transaction }) => {
  const { checkWithdrawalCompletion } = useTransactionHistory();
  const [isChecking, setIsChecking] = useState(false);
  const [lastChecked, setLastChecked] = useState<Date | null>(null);
  const [error, setError] = useState<string | null>(null);

  const isWithdrawalComplete = transaction.type === 'completeWithdrawal' &&
    transaction.status === 'confirmed' &&
    transaction.receiptTransactionHash;

  const handleManualCheck = async () => {
    if (!transaction.messageId || !transaction.txHash) {
      setError('Missing messageId or transaction hash');
      return;
    }

    setIsChecking(true);
    setError(null);

    try {
      await checkWithdrawalCompletion(transaction.messageId, transaction.txHash);
      setLastChecked(new Date());
    } catch (err: any) {
      setError(err.message || 'Failed to check withdrawal completion');
    } finally {
      setIsChecking(false);
    }
  };

  useEffect(() => {
    // Reset error if transaction changes
    setError(null);
  }, [transaction]);

  return (
    <div className="withdrawal-completion-status">
      {transaction.type === 'completeWithdrawal' && (
        <div className="status-container">
          <div className="status-header">
            <h4>Withdrawal Status</h4>
            {isWithdrawalComplete ? (
              <span className="status-badge complete">Complete</span>
            ) : (
              <span className="status-badge pending">Pending Completion</span>
            )}
          </div>

          {!isWithdrawalComplete && (
            <div className="action-container">
              <button
                onClick={handleManualCheck}
                disabled={isChecking}
                className="check-button"
              >
                {isChecking ? 'Checking...' : 'Check Completion Status'}
              </button>

              {lastChecked && (
                <div className="last-checked">
                  Last checked: {lastChecked.toLocaleTimeString()}
                </div>
              )}

              {error && (
                <div className="error-message">
                  {error}
                </div>
              )}
            </div>
          )}

          {isWithdrawalComplete && transaction.receiptTransactionHash && (
            <div className="completion-details">
              <p>Withdrawal has been completed on the destination chain.</p>
              <div className="receipt-hash">
                Receipt Transaction:
                <a
                  href={`https://sepolia.etherscan.io/tx/${transaction.receiptTransactionHash}`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  {`${transaction.receiptTransactionHash.substring(0, 10)}...`}
                </a>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};

export default WithdrawalCompletionStatus;