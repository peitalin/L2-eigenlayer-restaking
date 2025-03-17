import React, { useState, useEffect } from 'react';
import { useClientsContext } from '../contexts/ClientsContext';
import { formatEther, Address } from 'viem';
import { STRATEGY_MANAGER_ADDRESS, STRATEGY } from '../addresses';
import { StrategyManagerABI } from '../abis';

interface Deposit {
  strategy: Address;
  shares: string;
  strategyName: string;
}

// Helper function to get a human-readable name for a strategy
const getStrategyName = (strategyAddress: Address): string => {
  // Compare with known strategy addresses
  if (strategyAddress.toLowerCase() === STRATEGY.toLowerCase()) {
    return "Eigenlayer MAGIC Strategy";
  }

  // For unknown strategies, shorten the address
  return `${strategyAddress.substring(0, 6)}...${strategyAddress.substring(strategyAddress.length - 4)}`;
};

const UserDeposits: React.FC = () => {
  const { l1Wallet, isConnected, eigenAgentInfo } = useClientsContext();
  const [deposits, setDeposits] = useState<Deposit[]>([]);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // Function to fetch deposits from the StrategyManager contract
  const fetchDeposits = async () => {
    if (!isConnected || !eigenAgentInfo?.eigenAgentAddress || !l1Wallet.publicClient) {
      setDeposits([]);
      return;
    }

    try {
      setIsLoading(true);
      setError(null);

      // Call the getDeposits function on the StrategyManager contract
      const result = await l1Wallet.publicClient.readContract({
        address: STRATEGY_MANAGER_ADDRESS,
        abi: StrategyManagerABI,
        functionName: 'getDeposits',
        args: [eigenAgentInfo.eigenAgentAddress]
      });

      // Process the results
      const [strategies, shares] = result as [Address[], bigint[]];

      // Map the results to a more user-friendly format
      const depositList: Deposit[] = strategies.map((strategy, index) => ({
        strategy,
        shares: shares[index].toString(),
        strategyName: getStrategyName(strategy)
      }));

      setDeposits(depositList);
    } catch (err) {
      console.error('Error fetching deposits:', err);
      setError('Failed to fetch deposits. Please try again later.');
    } finally {
      setIsLoading(false);
    }
  };

  // Fetch deposits when the component mounts or when the wallet connection changes
  useEffect(() => {
    fetchDeposits();
  }, [eigenAgentInfo?.eigenAgentAddress, isConnected]);

  // If not connected, show a message
  if (!isConnected) {
    return (
      <div className="user-deposits">
        <h3>Your Deposits</h3>
        <p className="no-deposits-message">Connect your wallet to view your deposits.</p>
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

      {error && (
        <div className="deposits-error">
          {error}
        </div>
      )}

      {isLoading ? (
        <div className="deposits-loading">Loading deposits...</div>
      ) : deposits.length === 0 ? (
        <p className="no-deposits-message">No deposits found.</p>
      ) : (
        <div className="deposits-list">
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
                  <td className="deposit-strategy">
                    <div className="strategy-name">{deposit.strategyName}</div>
                    <div className="strategy-address" title={deposit.strategy}>{deposit.strategy}</div>
                  </td>
                  <td className="deposit-shares">
                    {formatEther(BigInt(deposit.shares))}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};

export default UserDeposits;