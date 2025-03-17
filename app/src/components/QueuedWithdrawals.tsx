import React, { useState, useEffect } from 'react';
import { formatEther, Address } from 'viem';
import { useClientsContext } from '../contexts/ClientsContext';
import { DelegationManagerABI } from '../abis';
import { DELEGATION_MANAGER_ADDRESS } from '../addresses';
import { blockNumberToTimestamp, formatBlockTimestamp, getMinWithdrawalDelayBlocks } from '../utils/eigenlayerUtils';

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
}

interface QueuedWithdrawalsData {
  withdrawals: ProcessedWithdrawal[];
  shares: bigint[][];
  minWithdrawalDelayBlocks: bigint;
}

const QueuedWithdrawals: React.FC = () => {
  const { eigenAgentInfo, isConnected, l1Wallet } = useClientsContext();
  const [queuedWithdrawals, setQueuedWithdrawals] = useState<QueuedWithdrawalsData | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [withdrawalRoots, setWithdrawalRoots] = useState<string[]>([]);

  const fetchQueuedWithdrawals = async () => {
    if (!isConnected || !eigenAgentInfo?.eigenAgentAddress || !l1Wallet.publicClient) {
      return;
    }

    try {
      setIsLoading(true);
      setError(null);

      // Fetch the minimum withdrawal delay blocks
      const minDelay = await getMinWithdrawalDelayBlocks();

      // Fetch queued withdrawals from the DelegationManager contract
      const result = await l1Wallet.publicClient.readContract({
        address: DELEGATION_MANAGER_ADDRESS,
        abi: DelegationManagerABI,
        functionName: 'getQueuedWithdrawals',
        args: [eigenAgentInfo.eigenAgentAddress]
      }) as [Withdrawal[], bigint[][]];

      // Process withdrawals to add end block and timestamp
      const processedWithdrawals: ProcessedWithdrawal[] = await Promise.all(
        result[0].map(async (withdrawal) => {
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

          return {
            ...withdrawal,
            endBlock,
            canWithdrawAfter
          };
        })
      );

      setQueuedWithdrawals({
        withdrawals: processedWithdrawals,
        shares: result[1],
        minWithdrawalDelayBlocks: minDelay
      });

      // Also fetch withdrawal roots
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

  // Helper function to render withdrawal time
  const renderWithdrawalTime = (withdrawal: ProcessedWithdrawal): string => {
    if (withdrawal.canWithdrawAfter) {
      return withdrawal.canWithdrawAfter;
    }

    return withdrawal.startBlock.toString() === '0' ? 'Pending' : 'Calculating...';
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
        <h3>On-Chain Queued Withdrawals</h3>
        <button
          onClick={fetchQueuedWithdrawals}
          disabled={isLoading}
          className="refresh-withdrawals-button"
          title="Refresh queued withdrawals"
        >
          {isLoading ? '...' : '⟳'}
        </button>
      </div>

      {error && (
        <div className="withdrawals-error">
          {error}
        </div>
      )}

      {isLoading ? (
        <div className="withdrawals-loading">Loading queued withdrawals...</div>
      ) : queuedWithdrawals && queuedWithdrawals.withdrawals.length > 0 ? (
        <div className="withdrawals-list">
          <h4>Withdrawal Details</h4>
          <p className="withdrawal-delay-info">
            Minimum withdrawal delay: {queuedWithdrawals.minWithdrawalDelayBlocks.toString()} blocks
          </p>
          <table className="withdrawals-table">
            <thead>
              <tr>
                <th>Nonce</th>
                <th>Strategies</th>
                <th>Shares</th>
                <th>Start Block</th>
                <th>End Block</th>
                <th>Can Withdraw After</th>
                <th>Withdrawer</th>
              </tr>
            </thead>
            <tbody>
              {queuedWithdrawals.withdrawals.map((withdrawal, index) => (
                <tr key={index} className="withdrawal-item">
                  <td>{withdrawal.nonce.toString()}</td>
                  <td className="withdrawal-strategies">
                    {withdrawal.strategies.map((strategy, idx) => (
                      <div key={idx}>{formatAddress(strategy)}</div>
                    ))}
                  </td>
                  <td className="withdrawal-shares">
                    {queuedWithdrawals.shares[index].map((share, idx) => (
                      <div key={idx}>{formatEther(share)}</div>
                    ))}
                  </td>
                  <td>{withdrawal.startBlock.toString()}</td>
                  <td>{withdrawal.endBlock.toString()}</td>
                  <td className="withdrawal-timestamp">
                    {renderWithdrawalTime(withdrawal)}
                  </td>
                  <td className="withdrawal-withdrawer">{formatAddress(withdrawal.withdrawer)}</td>
                </tr>
              ))}
            </tbody>
          </table>

          {withdrawalRoots.length > 0 && (
            <>
              <h4>Withdrawal Roots</h4>
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