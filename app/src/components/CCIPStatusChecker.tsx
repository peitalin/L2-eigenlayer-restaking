import React from 'react';
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
        {/* <button
          className="ccip-check-button"
          onClick={handleCheckStatus}
          disabled={isLoading || !messageId}
          title={isWithdrawal ? "Check Withdrawal Status" : "Check CCIP Status"}
        >
          {isLoading ? '...' : '⟳'}
        </button> */}
      </div>
    </div>
  );
};

export default CCIPStatusChecker;