import React, { useState, useEffect } from 'react';
import { formatEther, Address } from 'viem';
import { useClientsContext } from '../contexts/ClientsContext';
import { DelegationManagerABI } from '../abis';
import { DELEGATION_MANAGER_ADDRESS } from '../addresses';
import { blockNumberToTimestamp, formatBlockTimestamp, getMinWithdrawalDelayBlocks, calculateWithdrawalRoot } from '../utils/eigenlayerUtils';
import { useToast } from './ToastContainer';

// Define types for the withdrawal data structure based on the Solidity contract
interface Withdrawal {
  strategies: Address[];
  nonce: bigint;
  startBlock: bigint;
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
              delegatedAddress,
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

  // Call fetchQueuedWithdrawals when dependencies change
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

  if (!isConnected) {
    return (
      <div className="queued-withdrawals">
        <h3>On-Chain Queued Withdrawals</h3>
        <p className="no-withdrawals-message">Connect your wallet to view queued withdrawals.</p>
      </div>
    );
  }

  return (
    <div className="queued-withdrawals">
      <div className="queued-withdrawals-header">
        <h3>Queued Withdrawals</h3>
        <button
          onClick={fetchQueuedWithdrawals}
          disabled={isLoading}
          className="refresh-withdrawals-button"
          title="Refresh queued withdrawals"
        >
          {isLoading ? '...' : '⟳'}
        </button>
      </div>

      {isLoading ? (
        <div className="withdrawals-loading">Loading queued withdrawals...</div>
      ) : queuedWithdrawals && queuedWithdrawals.withdrawals.length > 0 ? (
        <div className="withdrawals-list">
          <table className="withdrawals-table">
            <thead>
              <tr>
                <th>Shares</th>
                <th>End Block</th>
                <th>Status</th>
                <th>Withdrawer</th>
                <th>Withdrawal Root</th>
                {onSelectWithdrawal && <th>Actions</th>}
              </tr>
            </thead>
            <tbody>
              {queuedWithdrawals.withdrawals.map((withdrawal, index) => (
                <tr key={index} className="withdrawal-item">
                  <td className="withdrawal-shares">
                    {queuedWithdrawals.shares[index].map((share, idx) => (
                      <div key={idx}>{formatEther(share)}</div>
                    ))}
                  </td>
                  <td>{withdrawal.endBlock.toString()}</td>
                  <td className="withdrawal-status">
                    {canCompleteWithdrawal(withdrawal) ?
                      <span className="ready">Ready</span> :
                      <span className="pending">Pending</span>
                    }
                  </td>
                  <td className="withdrawal-withdrawer">{formatAddress(withdrawal.withdrawer)}</td>
                  <td className="withdrawal-root-cell">
                    {withdrawal.withdrawalRoot ?
                      <div
                        className="withdrawal-root-hash-compact"
                        onClick={() => withdrawal.withdrawalRoot && handleWithdrawalRootClick(withdrawal.withdrawalRoot)}
                        title={withdrawal.withdrawalRoot}
                      >
                        {truncateWithdrawalRoot(withdrawal.withdrawalRoot)}
                      </div> :
                      <span className="no-root">Not available</span>
                    }
                  </td>
                  {onSelectWithdrawal && (
                    <td>
                      <button
                        onClick={() => handleCompleteClick(withdrawal, queuedWithdrawals.shares[index], index)}
                        disabled={!canCompleteWithdrawal(withdrawal) || completingWithdrawalIndex === index}
                        className="complete-withdrawal-button"
                      >
                        {completingWithdrawalIndex === index
                          ? 'Processing...'
                          : canCompleteWithdrawal(withdrawal)
                            ? 'Complete'
                            : 'Not Ready'}
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>

          {withdrawalRoots.length > 0 && (
            <>
              <h4>On-Chain Withdrawal Roots</h4>
              <div className="withdrawal-roots">
                {withdrawalRoots.map((root, index) => (
                  <div key={index} className="withdrawal-root">
                    {root}
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
      ) : (
        <p className="no-withdrawals-message">No queued withdrawals found on-chain.</p>
      )}
    </div>
  );
};

export default QueuedWithdrawals;