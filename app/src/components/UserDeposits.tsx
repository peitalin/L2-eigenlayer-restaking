import React, { useState, useEffect } from 'react';
import { formatEther, Address } from 'viem';
import { useClientsContext } from '../contexts/ClientsContext';
import { StrategyManagerABI } from '../abis';
import { STRATEGY_MANAGER_ADDRESS, STRATEGY } from '../addresses';
import { useToast } from '../utils/toast';

interface UserDeposit {
  strategy: Address;
  shares: bigint;
}

const UserDeposits: React.FC = () => {
  const { l1Wallet, eigenAgentInfo, isConnected } = useClientsContext();
  const [deposits, setDeposits] = useState<UserDeposit[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { showToast } = useToast();

  const fetchDeposits = async () => {
    if (!isConnected || !eigenAgentInfo?.eigenAgentAddress || !l1Wallet.publicClient) {
      return;
    }

    try {
      setIsLoading(true);
      setError(null);

      // Call getDeposits function on the StrategyManager contract
      const stakerStrategies = await l1Wallet.publicClient.readContract({
        address: STRATEGY_MANAGER_ADDRESS,
        abi: StrategyManagerABI,
        functionName: 'getDeposits',
        args: [eigenAgentInfo.eigenAgentAddress]
      }) as [Address[], bigint[]];

      // Convert to UserDeposit objects
      const depositItems: UserDeposit[] = stakerStrategies[0].map((strategy, index) => ({
        strategy,
        shares: stakerStrategies[1][index]
      }));

      setDeposits(depositItems);
    } catch (err) {
      console.error('Error fetching deposits:', err);
      setError('Failed to fetch deposits. Please try again later.');
      showToast('Failed to fetch deposits', 'error');
    } finally {
      setIsLoading(false);
    }
  };

  // Fetch deposits when component mounts or when dependencies change
  useEffect(() => {
    fetchDeposits();
  }, [eigenAgentInfo?.eigenAgentAddress, isConnected, l1Wallet.publicClient]);

  // Helper function to format an address for display
  const formatAddress = (address: Address): string => {
    return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
  };

  const getStrategyName = (address: Address): string => {
    if (address.toLowerCase() === STRATEGY.toLowerCase()) {
      return "MAGIC Strategy";
    }
    return formatAddress(address);
  };

  if (!isConnected) {
    return (
      <div className="treasure-card" style={{ border: 'none', paddingLeft: '0px', paddingRight: '0px' }}>
        <div className="treasure-card-header">
          <div className="treasure-card-title" style={{ fontSize: '1.1rem' }}>Your Deposits</div>
        </div>
        <div className="treasure-empty-state">
          <p className="treasure-empty-text">Connect your wallet to view deposits.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="treasure-card" style={{ border: 'none', paddingLeft: '0px', paddingRight: '0px' }}>
      <div className="treasure-card-header">
        <div className="treasure-card-title" style={{ fontSize: '1.1rem' }}>Your Deposits</div>
        <button
          onClick={fetchDeposits}
          disabled={isLoading}
          className="treasure-secondary-button"
          title="Refresh deposits"
          style={{ padding: '8px', minWidth: '36px' }}
        >
          {isLoading ? (
            <div className="loading-spinner"></div>
          ) : (
            '⟳'
          )}
        </button>
      </div>

      {error && (
        <div style={{
          backgroundColor: 'rgba(225, 30, 39, 0.1)',
          color: 'var(--treasure-error)',
          padding: '12px',
          borderRadius: '8px',
          marginBottom: '16px'
        }}>
          {error}
        </div>
      )}

      {isLoading ? (
        <div className="treasure-empty-state">
          <div className="loading-spinner"></div>
          <p className="treasure-empty-text">Loading deposits...</p>
        </div>
      ) : deposits.length > 0 ? (
        <div className="treasure-table-container">
          <table className="treasure-table">
            <thead>
              <tr>
                <th className="treasure-table-header">Strategy</th>
                <th className="treasure-table-header">Shares</th>
              </tr>
            </thead>
            <tbody>
              {deposits.map((deposit, index) => (
                <tr key={index} className="treasure-table-row">
                  <td className="treasure-table-cell font-mono" title={deposit.strategy}>
                    {getStrategyName(deposit.strategy)}
                  </td>
                  <td className="treasure-table-cell"
                    style={{ display: 'flex', alignItems: 'center', justifyContent: 'center'}}
                  >
                    <div className="magic-token-icon" style={{ marginRight: '8px' }}></div>
                    <span>{formatEther(deposit.shares)} MAGIC</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : (
        <div className="treasure-empty-state">
          <p className="treasure-empty-text">No deposits found.</p>
          <p className="treasure-empty-subtext">Deposit tokens first to see them here.</p>
        </div>
      )}
    </div>
  );
};

export default UserDeposits;