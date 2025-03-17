import React, { useState, useEffect, useMemo } from 'react';
import { baseSepolia } from '../hooks/useClients';
import { formatEther, parseEther, Hex, Address } from 'viem';
import { encodeDepositIntoStrategyMsg } from '../utils/encoders';
import { CHAINLINK_CONSTANTS, STRATEGY_MANAGER_ADDRESS, STRATEGY, SENDER_CCIP_ADDRESS } from '../addresses';
import { useClientsContext } from '../contexts/ClientsContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';

const HomePage: React.FC = () => {
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
  const [transactionAmount, setTransactionAmount] = useState<number>(0.11);
  const [expiryMinutes, setExpiryMinutes] = useState<number>(60);

  // Memoize the parsed amount to update whenever transactionAmount changes
  const amount = useMemo(() => {
    if (!transactionAmount) return parseEther("0");
    return parseEther(transactionAmount.toString());
  }, [transactionAmount]);

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
      setTransactionAmount(numValue);
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
    execute: executeDeposit,
    isExecuting,
    signature,
    error,
    isApprovingToken,
    approvalHash
  } = useEigenLayerOperation({
    targetContractAddr: STRATEGY_MANAGER_ADDRESS,
    messageToEigenlayer: encodeDepositIntoStrategyMsg(
      STRATEGY,
      CHAINLINK_CONSTANTS.ethSepolia.bridgeToken,
      amount
    ),
    amount,
    tokenApproval: {
      tokenAddress: CHAINLINK_CONSTANTS.baseSepolia.bridgeToken,
      spenderAddress: SENDER_CCIP_ADDRESS,
      amount
    },
    expiryMinutes,
    onSuccess: (txHash) => {
      alert(`Transaction sent! Hash: ${txHash}\nView on BaseScan: https://sepolia.basescan.org/tx/${txHash}`);
    },
    onError: (err) => {
      console.error('Error in deposit operation:', err);
    }
  });

  // Handle deposit into strategy
  const handleDepositIntoStrategy = async () => {
    if (!transactionAmount) {
      alert("Invalid transaction amount");
      return;
    }

    await executeDeposit();
  };

  // Check if we should disable inputs
  const isInputDisabled = !isConnected || isExecuting;

  return (
    <div className="home-page">
      <div className="page-layout">
        <div className="left-column">
          <div className="transaction-form">
            <h2>Deposit into Strategy</h2>

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
              <label htmlFor="amount">Token Amount:</label>
              <input
                id="amount"
                type="text"
                value={transactionAmount === 0 ? '' : transactionAmount.toString()}
                onChange={handleAmountChange}
                className="amount-input"
                placeholder="0.11"
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
              onClick={handleDepositIntoStrategy}
            >
              {isExecuting ? 'Processing...' : 'Sign Strategy Deposit'}
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

          {/* Token Approval Status */}
          {isApprovingToken && (
            <div className="approval-status">
              <h3>Token Approval Status</h3>
              <p>Approving token for spending...</p>
              {approvalHash && (
                <p>
                  Approval Transaction:
                  <a
                    href={`https://sepolia.basescan.org/tx/${approvalHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {approvalHash.substring(0, 10)}...
                  </a>
                </p>
              )}
            </div>
          )}

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
                You need to create an EigenAgent on Ethereum Sepolia before you can deposit into a strategy.
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

export default HomePage;