import React, { useState, useEffect, useMemo } from 'react';
import { baseSepolia } from '../hooks/useClients';
import { formatEther, parseEther, Hex, Address } from 'viem';
import { encodeQueueWithdrawalMsg, ZeroAddress } from '../utils/encoders';
import { CHAINLINK_CONSTANTS, STRATEGY_MANAGER_ADDRESS, STRATEGY, SENDER_CCIP_ADDRESS, DELEGATION_MANAGER_ADDRESS } from '../addresses';
import { useClientsContext } from '../contexts/ClientsContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { DelegationManagerABI } from '../abis';
import QueuedWithdrawals from './QueuedWithdrawals';

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
  const [withdrawalAmount, setWithdrawalAmount] = useState<string>('0.05');
  const [expiryMinutes, setExpiryMinutes] = useState<number>(60);
  const [withdrawalNonce, setWithdrawalNonce] = useState<bigint>(0n);
  const [delegatedTo, setDelegatedTo] = useState<Address | null>(null);
  const [isLoadingL1Data, setIsLoadingL1Data] = useState<boolean>(false);

  // Memoize the parsed amount to update whenever withdrawalAmount changes
  const amount = useMemo(() => {
    if (!withdrawalAmount || withdrawalAmount === '.') return parseEther("0");
    try {
      return parseEther(withdrawalAmount);
    } catch (error) {
      console.error('Error parsing amount:', error);
      return parseEther("0");
    }
  }, [withdrawalAmount]);

  // Add a useEffect that will run once when the component mounts
  useEffect(() => {
    // Check if we already have the l1Account and still need to fetch eigenAgentInfo
    if (l1Wallet.account && !eigenAgentInfo && isConnected) {
      fetchEigenAgentInfo();
    }
  }, [l1Wallet.account, eigenAgentInfo, isConnected, fetchEigenAgentInfo]);

  // Fetch L1 data needed for withdrawal
  useEffect(() => {
    const fetchL1Data = async () => {
      if (!isConnected || !eigenAgentInfo || !l1Wallet.publicClient) {
        return;
      }

      try {
        setIsLoadingL1Data(true);

        // Get the withdrawalNonce from DelegationManager using the imported ABI
        const nonce = await l1Wallet.publicClient.readContract({
          address: DELEGATION_MANAGER_ADDRESS,
          abi: DelegationManagerABI,
          functionName: 'cumulativeWithdrawalsQueued',
          args: [eigenAgentInfo.eigenAgentAddress]
        });

        // Get the delegatedTo address from DelegationManager using the imported ABI
        const delegated = await l1Wallet.publicClient.readContract({
          address: DELEGATION_MANAGER_ADDRESS,
          abi: DelegationManagerABI,
          functionName: 'delegatedTo',
          args: [eigenAgentInfo.eigenAgentAddress]
        });

        setWithdrawalNonce(nonce as bigint);
        setDelegatedTo(delegated as Address);
      } catch (err) {
        console.error('Error fetching L1 data:', err);
      } finally {
        setIsLoadingL1Data(false);
      }
    };

    fetchL1Data();
  }, [eigenAgentInfo, isConnected, l1Wallet.publicClient]);

  // Handle amount input changes with validation
  const handleAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    // Allow only valid number inputs (digits, one decimal point, and decimal digits)
    if (value === '' || /^(\d*\.?\d*)$/.test(value)) {
      setWithdrawalAmount(value);
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
    targetContractAddr: DELEGATION_MANAGER_ADDRESS,
    messageToEigenlayer: encodeQueueWithdrawalMsg(
        STRATEGY,
        amount,
        eigenAgentInfo?.eigenAgentAddress || ZeroAddress
    ),
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
    const numValue = withdrawalAmount ? parseFloat(withdrawalAmount) : 0;
    if (isNaN(numValue) || numValue <= 0) {
      alert("Withdrawal amount must be greater than zero");
      return;
    }

    if (!eigenAgentInfo) {
      alert("No EigenAgent found. Cannot proceed with withdrawal.");
      return;
    }

    try {
      await executeWithdrawal();
    } catch (err) {
      console.error('Error in withdrawal:', err);
      alert(`Error: ${err instanceof Error ? err.message : 'Unknown error occurred'}`);
    }
  };

  // Check if we should disable inputs
  const isInputDisabled = !isConnected || isExecuting || isLoadingL1Data;

  return (
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
        <label htmlFor="receiver">Target Address (Delegation Manager):</label>
        <input
          id="receiver"
          type="text"
          value={DELEGATION_MANAGER_ADDRESS}
          onChange={() => {}}
          className="receiver-input"
          placeholder="0x..."
          disabled={true}
        />
        <div className="input-note">Using DelegationManager for Queue Withdrawals</div>
      </div>

      {isConnected && eigenAgentInfo && (
        <div className="form-group">
          <label>Withdrawal Information:</label>
          <div className="info-item">
            <strong>Current Withdrawal Nonce:</strong> {isLoadingL1Data ? 'Loading...' : withdrawalNonce.toString()}
          </div>
          <div className="info-item">
            <strong>Delegated To:</strong> {isLoadingL1Data ? 'Loading...' : (delegatedTo ? delegatedTo : 'Not delegated')}
          </div>
          <div className="info-item">
            <strong>Withdrawer Address:</strong> {eigenAgentInfo.eigenAgentAddress}
            <div className="input-note">Your EigenAgent will be set as the withdrawer</div>
          </div>
        </div>
      )}

      <div className="form-group">
        <label htmlFor="amount">Token Amount to Withdraw:</label>
        <input
          id="amount"
          type="text"
          value={withdrawalAmount}
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
        disabled={isInputDisabled || !eigenAgentInfo}
        onClick={handleQueueWithdrawal}
      >
        {isExecuting ? 'Processing...' : isLoadingL1Data ? 'Loading L1 Data...' : 'Queue Withdrawal'}
      </button>

      <div className="withdrawal-info">
        <h3>About Withdrawals</h3>
        <p>
          Queue a withdrawal to start the withdrawal process. After queueing,
          you'll need to wait for the unbonding period to complete before you can complete the withdrawal.
        </p>
        <p>
          The unbonding period is typically 7 days for EigenLayer strategies.
        </p>
        <p>
          <strong>Note:</strong> Although the withdrawer field is deprecated in the EigenLayer contracts,
          it is still required by the protocol. Your EigenAgent address is automatically set as
          the withdrawer for this transaction. The actual withdrawal will be executed by your EigenAgent
          after the unbonding period.
        </p>
      </div>

      {error && (
        <div className="error-message">
          {error}
        </div>
      )}

      <div className="withdrawals-section">
        <QueuedWithdrawals />
      </div>
    </div>
  );
};

export default WithdrawalPage;
