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
      <div className="user-deposits">
        <h3>Your Deposits</h3>
        <p className="no-deposits-message">Connect your wallet to view deposits.</p>
      </div>
    );
  }

  return (
    <div className="user-deposits">
      <div className="user-deposits-header">
        <h3>Your Deposits</h3>
        <button
          onClick={fetchDeposits}
          disabled={isLoading}
          className="refresh-deposits-button"
          title="Refresh deposits"
        >
          {isLoading ? '...' : '⟳'}
        </button>
      </div>

      {error && <div className="deposits-error">{error}</div>}

      {isLoading ? (
        <div className="deposits-loading">Loading deposits...</div>
      ) : deposits.length > 0 ? (
        <table className="deposits-table">
          <thead>
            <tr>
              <th>Strategy</th>
              <th>Shares</th>
            </tr>
          </thead>
          <tbody>
            {deposits.map((deposit, index) => (
              <tr key={index} className="deposit-item">
                <td className="strategy-address" title={deposit.strategy}>
                  {getStrategyName(deposit.strategy)}
                </td>
                <td className="deposit-shares">{formatEther(deposit.shares)} MAGIC</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <p className="no-deposits-message">No deposits found. Deposit tokens first.</p>
      )}
    </div>
  );
};

export default UserDeposits;