import React, { useState, useEffect, useMemo } from 'react';
import { baseSepolia } from '../hooks/useClients';
import { formatEther, parseEther, Hex, Address } from 'viem';
import { encodeQueueWithdrawalMsg } from '../utils/encoders';
import { CHAINLINK_CONSTANTS, STRATEGY_MANAGER_ADDRESS, STRATEGY, SENDER_CCIP_ADDRESS } from '../addresses';
import { useClientsContext } from '../contexts/ClientsContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';

const WithdrawalPage: React.FC = () => {
  const {
    l1Wallet,
    l2Wallet,
    selectedChain,
    isConnected,
    switchChain,
    isLoadingBalance,
    refreshBalances,
    eigenAgentInfo,
    isLoadingEigenAgent,
    fetchEigenAgentInfo
  } = useClientsContext();

  // State for transaction details
  const [withdrawalAmount, setWithdrawalAmount] = useState<number>(0.05);
  const [expiryMinutes, setExpiryMinutes] = useState<number>(60);

  // Memoize the parsed amount to update whenever withdrawalAmount changes
  const amount = useMemo(() => {
    if (!withdrawalAmount) return parseEther("0");
    return parseEther(withdrawalAmount.toString());
  }, [withdrawalAmount]);

  // Add a useEffect that will run once when the component mounts
  useEffect(() => {
    // Check if we already have the l1Account and still need to fetch eigenAgentInfo
    if (l1Wallet.account && !eigenAgentInfo && isConnected) {
      fetchEigenAgentInfo();
    }
  }, [l1Wallet.account, eigenAgentInfo, isConnected, fetchEigenAgentInfo]);

  // Handle amount input changes with validation
  const handleAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    // Allow only valid number inputs
    if (value === '' || /^\d*\.?\d*$/.test(value)) {
      const numValue = value === '' ? 0 : parseFloat(value);
      setWithdrawalAmount(numValue);
    }
  };

  // Handle expiry minutes changes
  const handleExpiryChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = parseInt(e.target.value);
    if (!isNaN(value) && value > 0) {
      setExpiryMinutes(value);
    }
  };

  // Use the EigenLayer operation hook
  const {
    execute: executeWithdrawal,
    isExecuting,
    signature,
    error,
    isApprovingToken,
    approvalHash
  } = useEigenLayerOperation({
    targetContractAddr: STRATEGY_MANAGER_ADDRESS,
    messageToEigenlayer: encodeQueueWithdrawalMsg(
      STRATEGY,
      amount
    ),
    // No tokens are sent for withdrawals
    amount: 0n,
    expiryMinutes,
    onSuccess: (txHash) => {
      alert(`Withdrawal queued! Transaction hash: ${txHash}\nView on BaseScan: https://sepolia.basescan.org/tx/${txHash}`);
    },
    onError: (err) => {
      console.error('Error in withdrawal operation:', err);
    }
  });

  // Handle queueing withdrawal from strategy
  const handleQueueWithdrawal = async () => {
    if (!withdrawalAmount) {
      alert("Invalid withdrawal amount");
      return;
    }

    await executeWithdrawal();
  };

  // Check if we should disable inputs
  const isInputDisabled = !isConnected || isExecuting;

  return (
    <div className="withdrawal-page">
      <div className="page-layout">
        <div className="left-column">
          <div className="transaction-form">
            <h2>Queue Withdrawal from Strategy</h2>

            <div className="account-balances">
              <h3>Account Balances</h3>
              <div className="balance-item">
                <span className="balance-label">Ethereum Sepolia:</span>
                <span className="balance-value">
                  {isConnected && l1Wallet.balance ? `${formatEther(BigInt(l1Wallet.balance))} ETH` : 'Not Connected'}
                </span>
              </div>
              <div className="balance-item">
                <span className="balance-label">Base Sepolia:</span>
                <span className="balance-value">
                  {isConnected && l2Wallet.balance ? `${formatEther(BigInt(l2Wallet.balance))} ETH` : 'Not Connected'}
                </span>
                {isConnected && (
                  <button
                    onClick={refreshBalances}
                    disabled={isLoadingBalance || !isConnected}
                    className="refresh-balance-button"
                  >
                    {isLoadingBalance ? '...' : '⟳'}
                  </button>
                )}
              </div>
            </div>

            <div className="form-group">
              <label htmlFor="receiver">Target Address (Strategy Manager):</label>
              <input
                id="receiver"
                type="text"
                value={STRATEGY_MANAGER_ADDRESS}
                onChange={() => {}}
                className="receiver-input"
                placeholder="0x..."
                disabled={true}
              />
              <div className="input-note">Using CCIP Strategy from EigenLayer contracts</div>
            </div>

            <div className="form-group">
              <label htmlFor="amount">Token Amount to Withdraw:</label>
              <input
                id="amount"
                type="text"
                value={withdrawalAmount === 0 ? '' : withdrawalAmount.toString()}
                onChange={handleAmountChange}
                className="amount-input"
                placeholder="0.05"
                disabled={isInputDisabled}
              />
              <div className="input-note">Using EigenLayer TokenERC20</div>
            </div>

            <div className="form-group">
              <label htmlFor="expiry">Expiry (minutes from now):</label>
              <input
                id="expiry"
                type="number"
                min="1"
                value={expiryMinutes}
                onChange={handleExpiryChange}
                className="expiry-input"
                disabled={isInputDisabled}
              />
            </div>

            <button
              className="create-transaction-button"
              disabled={isInputDisabled || !eigenAgentInfo?.eigenAgentAddress}
              onClick={handleQueueWithdrawal}
            >
              {isExecuting ? 'Processing...' : 'Queue Withdrawal'}
            </button>
          </div>
        </div>

        <div className="right-column">
          <div className="eigenagent-info">
            <h3>EigenAgent Information (Ethereum Sepolia)</h3>
            {!isConnected ? (
              <p>Connect your wallet to view EigenAgent information</p>
            ) : !l1Wallet.account ? (
              <p>Connect your wallet to view EigenAgent information</p>
            ) : isLoadingEigenAgent ? (
              <p>Loading EigenAgent info...</p>
            ) : eigenAgentInfo ? (
              <div>
                {eigenAgentInfo.eigenAgentAddress ? (
                  <>
                    <div className="eigenagent-address">
                      <strong>EigenAgent Address:</strong> {eigenAgentInfo.eigenAgentAddress}
                    </div>
                    <div className="execution-nonce">
                      <strong>Execution Nonce:</strong> {eigenAgentInfo.execNonce.toString()}
                    </div>
                  </>
                ) : (
                  <p>No EigenAgent found for this wallet</p>
                )}
                <button
                  onClick={fetchEigenAgentInfo}
                  className="eigenagent-check-button"
                  disabled={isLoadingEigenAgent || !isConnected}
                >
                  Refresh EigenAgent Info
                </button>
              </div>
            ) : (
              <p>Failed to load EigenAgent information</p>
            )}
          </div>

          <div className="withdrawal-info">
            <h3>About Withdrawals</h3>
            <p>
              Queueing a withdrawal is the first step in the withdrawal process. After queueing,
              you'll need to wait for the unbonding period to complete before you can complete the withdrawal.
            </p>
            <p>
              The unbonding period is typically 7 days for EigenLayer strategies.
            </p>
          </div>

          {!isConnected && (
            <div className="connection-message">
              <h3>Wallet Not Connected</h3>
              <p>
                Please connect your wallet using the "Connect" button in the navigation bar
                to interact with EigenLayer.
              </p>
            </div>
          )}

          {isConnected && !eigenAgentInfo?.eigenAgentAddress && (
            <div className="no-agent-warning">
              <h3>No EigenAgent Found</h3>
              <p>
                You need to create an EigenAgent on Ethereum Sepolia before you can queue withdrawals from a strategy.
              </p>
            </div>
          )}
        </div>
      </div>

      {error && (
        <div className="error-message">
          {error}
        </div>
      )}
    </div>
  );
};

export default WithdrawalPage;

