import React, { useState, useEffect } from 'react';
import { formatEther, Address } from 'viem';
import { useClientsContext } from '../contexts/ClientsContext';
import { DelegationManagerABI } from '../abis';
import { DELEGATION_MANAGER_ADDRESS } from '../addresses';
import { blockNumberToTimestamp, formatBlockTimestamp, getMinWithdrawalDelayBlocks, calculateWithdrawalRoot } from '../utils/eigenlayerUtils';
import { useToast } from '../utils/toast';

// Define types for the withdrawal data structure based on the Solidity contract
interface Withdrawal {
  delegatedTo: Address;
  nonce: bigint;
  scaledShares: bigint[];
  staker: Address;
  startBlock: bigint;
  strategies: Address[];
  withdrawer: Address;
}

interface ProcessedWithdrawal extends Withdrawal {
  endBlock: bigint;
  canWithdrawAfter: string | null;
  withdrawalRoot?: string;
}

interface QueuedWithdrawalsData {
  withdrawals: ProcessedWithdrawal[];
  shares: bigint[][];
  minWithdrawalDelayBlocks: bigint;
}

interface QueuedWithdrawalsProps {
  onSelectWithdrawal?: (withdrawal: ProcessedWithdrawal, sharesArray: bigint[]) => void;
  isCompletingWithdrawal?: boolean;
}

const QueuedWithdrawals: React.FC<QueuedWithdrawalsProps> = ({
  onSelectWithdrawal,
  isCompletingWithdrawal = false
}) => {
  const { eigenAgentInfo, isConnected, l1Wallet } = useClientsContext();
  const [queuedWithdrawals, setQueuedWithdrawals] = useState<QueuedWithdrawalsData | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [withdrawalRoots, setWithdrawalRoots] = useState<string[]>([]);
  const [completingWithdrawalIndex, setCompletingWithdrawalIndex] = useState<number | null>(null);
  const [delegatedTo, setDelegatedTo] = useState<Address | null>(null);
  const { showToast } = useToast();

  // Reset the completing withdrawal index when isCompletingWithdrawal changes to false
  // This ensures our button state is reset when a transaction is rejected
  useEffect(() => {
    if (!isCompletingWithdrawal && completingWithdrawalIndex !== null) {
      setCompletingWithdrawalIndex(null);
    }
  }, [isCompletingWithdrawal]);

  const fetchQueuedWithdrawals = async () => {
    if (!isConnected || !eigenAgentInfo?.eigenAgentAddress || !l1Wallet.publicClient) {
      return;
    }

    try {
      setIsLoading(true);
      setError(null);

      // Fetch the minimum withdrawal delay blocks
      const minDelay = await getMinWithdrawalDelayBlocks();

      // Fetch delegated address for withdrawal root calculation
      const delegatedAddress = await l1Wallet.publicClient.readContract({
        address: DELEGATION_MANAGER_ADDRESS,
        abi: DelegationManagerABI,
        functionName: 'delegatedTo',
        args: [eigenAgentInfo.eigenAgentAddress]
      }) as Address;

      setDelegatedTo(delegatedAddress);

      // Fetch queued withdrawals from the DelegationManager contract
      const result = await l1Wallet.publicClient.readContract({
        address: DELEGATION_MANAGER_ADDRESS,
        abi: DelegationManagerABI,
        functionName: 'getQueuedWithdrawals',
        args: [eigenAgentInfo.eigenAgentAddress]
      }) as [Withdrawal[], bigint[][]];

      // Process withdrawals to add end block and timestamp
      const processedWithdrawals: ProcessedWithdrawal[] = await Promise.all(
        result[0].map(async (withdrawal, index) => {
          // Ensure all values are the right type
          const startBlock = BigInt(withdrawal.startBlock.toString());

          // Calculate end block (start block + delay)
          const endBlock = startBlock + BigInt(minDelay.toString());

          let canWithdrawAfter: string | null = null;

          // Only calculate timestamp if startBlock is not zero
          if (startBlock > 0n) {
            try {
              // Make sure we're passing a BigInt to the timestamp function
              const endTimestamp = await blockNumberToTimestamp(endBlock);
              canWithdrawAfter = formatBlockTimestamp(endTimestamp);
            } catch (err) {
              console.error(`Error calculating timestamp for block ${endBlock}:`, err);
            }
          }

          // Calculate withdrawal root if we have delegatedTo address
          let withdrawalRoot: string | undefined = undefined;
          try {
            withdrawalRoot = calculateWithdrawalRoot(
              eigenAgentInfo.eigenAgentAddress,
              withdrawal.delegatedTo,
              eigenAgentInfo.eigenAgentAddress,
              withdrawal.nonce,
              startBlock,
              withdrawal.strategies,
              result[1][index]
            );
          } catch (err) {
            console.error('Error calculating withdrawal root:', err);
          }

          return {
            ...withdrawal,
            endBlock,
            canWithdrawAfter,
            withdrawalRoot
          };
        })
      );

      setQueuedWithdrawals({
        withdrawals: processedWithdrawals,
        shares: result[1],
        minWithdrawalDelayBlocks: minDelay
      });

      // Also fetch withdrawal roots from contract
      const roots = await l1Wallet.publicClient.readContract({
        address: DELEGATION_MANAGER_ADDRESS,
        abi: DelegationManagerABI,
        functionName: 'getQueuedWithdrawalRoots',
        args: [eigenAgentInfo.eigenAgentAddress]
      }) as string[];

      setWithdrawalRoots(roots);

    } catch (err) {
      console.error('Error fetching queued withdrawals:', err);
      setError('Failed to fetch queued withdrawals. Please try again later.');
      showToast('Failed to fetch queued withdrawals. Please try again later.', 'error');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchQueuedWithdrawals();
  }, [eigenAgentInfo?.eigenAgentAddress, isConnected, l1Wallet.publicClient]);

  // Helper function to format an address for display
  const formatAddress = (address: Address) => {
    return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
  };

  // Show notification that withdrawal root was copied
  const handleWithdrawalRootClick = (root: string) => {
    // Copy to clipboard if supported
    if (navigator.clipboard) {
      navigator.clipboard.writeText(root)
        .then(() => {
          showToast('Withdrawal Root copied to clipboard', 'success');
        })
        .catch(() => {
          showToast('Failed to copy to clipboard, but here is the Withdrawal Root', 'info');
          showToast(root, 'info');
        });
    } else {
      showToast('Clipboard API not available, but here is the Withdrawal Root', 'info');
      showToast(root, 'info');
    }
  };

  // Helper function to truncate the withdrawal root for display
  const truncateWithdrawalRoot = (root: string): string => {
    if (!root) return '';
    return `${root.substring(0, 10)}...${root.substring(root.length - 8)}`;
  };

  // Helper function to render withdrawal time
  const renderWithdrawalTime = (withdrawal: ProcessedWithdrawal): string => {
    if (withdrawal.canWithdrawAfter) {
      return withdrawal.canWithdrawAfter;
    }

    return withdrawal.startBlock.toString() === '0' ? 'Pending' : 'Calculating...';
  };

  // Helper function to determine if a withdrawal is ready to be completed
  const canCompleteWithdrawal = (withdrawal: ProcessedWithdrawal): boolean => {
    // Check if startBlock is greater than 0 (withdrawal has been processed)
    if (withdrawal.startBlock <= 0n) return false;

    // Check if the current time is past the end time
    const currentTime = Math.floor(Date.now() / 1000);

    // If we don't have canWithdrawAfter timestamp, we'll just check if it's been 7 days
    if (!withdrawal.canWithdrawAfter) {
      // Default to 7 days from startBlock as a fallback
      const sevenDaysInSeconds = 7 * 24 * 60 * 60;
      return currentTime > (Number(withdrawal.startBlock) * 12 + sevenDaysInSeconds); // rough estimate
    }

    // Parse the canWithdrawAfter date
    const withdrawAfterDate = new Date(withdrawal.canWithdrawAfter).getTime() / 1000;
    return currentTime > withdrawAfterDate;
  };

  // Handle the complete withdrawal button click
  const handleCompleteClick = (withdrawal: ProcessedWithdrawal, sharesArray: bigint[], index: number) => {
    if (onSelectWithdrawal) {
      setCompletingWithdrawalIndex(index);
      onSelectWithdrawal(withdrawal, sharesArray);
    }
  };

  // When rendering a withdrawal root, check if it's in the on-chain roots and style accordingly
  const renderWithdrawalRoot = (root: string | undefined) => {
    if (!root) {
      return <span className="no-root">Not available</span>;
    }

    // Check if this root is in the on-chain roots list
    const isOnChain = withdrawalRoots.includes(root);

    return (
      <div
        className={`withdrawal-root-hash-compact ${isOnChain ? 'on-chain' : 'not-on-chain'}`}
        title={root}
      >
        {truncateWithdrawalRoot(root)}
      </div>
    );
  };

  // Update the button text to show "Ready in X time" instead of "Not Ready"
  const renderButtonText = (withdrawal: ProcessedWithdrawal, index: number) => {
    if (completingWithdrawalIndex === index) {
      return 'Processing...';
    }

    if (canCompleteWithdrawal(withdrawal)) {
      return 'Complete';
    }

    return `Ready in ${renderWithdrawalTime(withdrawal)}`;
  };

  if (!isConnected) {
    return (
      <div className="treasure-card">
        <div className="treasure-card-header">
          <div className="treasure-card-title">Queued Withdrawals</div>
        </div>
        <div className="treasure-empty-state">
          <div className="treasure-empty-icon">
            <span style={{ fontSize: '1.75rem' }}>🔌</span>
          </div>
          <div className="treasure-empty-text">Connect your wallet to view queued withdrawals.</div>
        </div>
      </div>
    );
  }

  return (
    <div className="treasure-card">
      <div className="treasure-card-header">
        <div className="treasure-card-title">Queued Withdrawals</div>
        <button
          onClick={fetchQueuedWithdrawals}
          disabled={isLoading}
          className="treasure-secondary-button"
          style={{ padding: '4px 12px', minWidth: 'auto' }}
          title="Refresh queued withdrawals"
        >
          {isLoading ? '...' : '⟳'}
        </button>
      </div>

      {isLoading ? (
        <div className="treasure-empty-state">
          <div className="loading-spinner"></div>
          <div className="treasure-empty-text">Loading queued withdrawals...</div>
        </div>
      ) : queuedWithdrawals && queuedWithdrawals.withdrawals.length > 0 ? (
        <div className="treasure-table-container">
          <table className="treasure-table">
            <thead>
              <tr>
                <th className="treasure-table-header">Shares</th>
                <th className="treasure-table-header">End Block</th>
                <th className="treasure-table-header">Status</th>
                <th className="treasure-table-header">Withdrawer</th>
                <th className="treasure-table-header">Withdrawal Root</th>
                {onSelectWithdrawal && <th className="treasure-table-header">Actions</th>}
              </tr>
            </thead>
            <tbody>
              {queuedWithdrawals.withdrawals.map((withdrawal, index) => (
                <tr key={index} className="treasure-table-row">
                  <td className="treasure-table-cell">
                    {queuedWithdrawals.shares[index].map((share, idx) => (
                      <div key={idx}>{formatEther(share)}</div>
                    ))}
                  </td>
                  <td className="treasure-table-cell">{withdrawal.endBlock.toString()}</td>
                  <td className="treasure-table-cell">
                    {canCompleteWithdrawal(withdrawal) ? (
                      <span className="treasure-status-ready">Ready</span>
                    ) : (
                      <span className="treasure-status-pending">Pending</span>
                    )}
                  </td>
                  <td className="treasure-table-cell font-mono">{formatAddress(withdrawal.withdrawer)}</td>
                  <td className="treasure-table-cell">
                    <div
                      className="treasure-withdrawal-root"
                      onClick={() => withdrawal.withdrawalRoot && handleWithdrawalRootClick(withdrawal.withdrawalRoot)}
                      style={{ cursor: withdrawal.withdrawalRoot ? 'pointer' : 'default' }}
                    >
                      {renderWithdrawalRoot(withdrawal.withdrawalRoot)}
                    </div>
                  </td>
                  {onSelectWithdrawal && (
                    <td className="treasure-table-cell">
                      <button
                        onClick={() => handleCompleteClick(withdrawal, queuedWithdrawals.shares[index], index)}
                        disabled={!canCompleteWithdrawal(withdrawal) || completingWithdrawalIndex === index}
                        className={`treasure-action-button ${!canCompleteWithdrawal(withdrawal) ? 'disabled' : ''}`}
                        style={{ padding: '8px 16px' }}
                      >
                        {renderButtonText(withdrawal, index)}
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="treasure-empty-state">
          <div className="treasure-empty-icon">
            <span style={{ fontSize: '1.75rem' }}>📋</span>
          </div>
          <div className="treasure-empty-text">No queued withdrawals found on-chain.</div>
          <div className="treasure-empty-subtext">Queue a withdrawal to see it here.</div>
        </div>
      )}
    </div>
  );
};

export default QueuedWithdrawals;