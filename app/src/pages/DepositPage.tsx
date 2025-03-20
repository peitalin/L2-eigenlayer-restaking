import React, { useState, useEffect, useMemo } from 'react';
import { formatEther, parseEther, Address } from 'viem';
import { encodeDepositIntoStrategyMsg } from '../utils/encoders';
import { STRATEGY_MANAGER_ADDRESS, STRATEGY, SENDER_CCIP_ADDRESS } from '../addresses';
import { BaseSepolia, EthSepolia } from '../addresses';
import { useClientsContext } from '../contexts/ClientsContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { useToast } from '../utils/toast';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { publicClients } from '../hooks/useClients';

// Add the Strategy ABI for the functions we need
const strategyAbi = [
  {
    name: 'totalShares',
    type: 'function',
    inputs: [],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view'
  },
  {
    name: 'sharesToUnderlyingView',
    type: 'function',
    inputs: [{ type: 'uint256', name: 'amountShares' }],
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view'
  },
  {
    name: 'underlyingToken',
    type: 'function',
    inputs: [],
    outputs: [{ type: 'address' }],
    stateMutability: 'view'
  }
];

const DepositPage: React.FC = () => {
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
    fetchEigenAgentInfo,
    predictedEigenAgentAddress,
    isFirstTimeUser
  } = useClientsContext();
  const { showToast } = useToast();

  // State for transaction details
  const [transactionAmount, setTransactionAmount] = useState<string>('0.11');
  const { addTransaction } = useTransactionHistory();

  // State for strategy stats
  const [totalShares, setTotalShares] = useState<bigint | null>(null);
  const [totalStaked, setTotalStaked] = useState<bigint | null>(null);
  const [isLoadingStrategyStats, setIsLoadingStrategyStats] = useState(false);

  // Memoize the parsed amount to update whenever transactionAmount changes
  const amount = useMemo(() => {
    if (!transactionAmount || transactionAmount === '.') return parseEther("0");
    try {
      return parseEther(transactionAmount);
    } catch (error) {
      console.error('Error parsing amount:', error);
      return parseEther("0");
    }
  }, [transactionAmount]);

  // Set appropriate gas limit based on whether this is a first-time user
  const gasLimit = useMemo(() => {
    return isFirstTimeUser ? BigInt(860_000) : BigInt(560_000);
  }, [isFirstTimeUser]);

  // Fetch strategy stats
  const fetchStrategyStats = async () => {

    // Use the public client from the exported publicClients object
    const sepoliaPublicClient = publicClients[11155111]; // Sepolia chain ID

    setIsLoadingStrategyStats(true);
    try {
      // Get the total shares
      const shares = await sepoliaPublicClient.readContract({
        address: STRATEGY as Address,
        abi: strategyAbi,
        functionName: 'totalShares'
      }) as bigint;

      setTotalShares(shares);

      // If there are shares, get the underlying token amount
      if (shares > 0n) {
        const underlying = await sepoliaPublicClient.readContract({
          address: STRATEGY as Address,
          abi: strategyAbi,
          functionName: 'sharesToUnderlyingView',
          args: [shares]
        }) as bigint;

        setTotalStaked(underlying);
      } else {
        setTotalStaked(0n);
      }
    } catch (error) {
      console.error('Error fetching strategy stats:', error);
      showToast('Failed to load strategy statistics', 'error');
    } finally {
      setIsLoadingStrategyStats(false);
    }
  };

  useEffect(() => {
    // Check if we already have the l1Account and still need to fetch eigenAgentInfo
    // Only fetch if not already loading and not already fetched
    if (l1Wallet.account && !eigenAgentInfo && isConnected && !isLoadingEigenAgent) {
      fetchEigenAgentInfo();
    }
    // Don't include eigenAgentInfo in deps to avoid refetching when it changes
  }, [l1Wallet.account, isConnected, isLoadingEigenAgent, fetchEigenAgentInfo]);

  // Fetch strategy stats when component mounts
  useEffect(() => {
    fetchStrategyStats();

  }, []);

  // Handle amount input changes with validation
  const handleAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    // Allow only valid number inputs (digits, one decimal point, and decimal digits)
    if (value === '' || /^(\d*\.?\d*)$/.test(value)) {
      setTransactionAmount(value);
    }
  };

  // Use the EigenLayer operation hook
  const {
    isExecuting,
    signature,
    error,
    info,
    isApprovingToken,
    approvalHash,
    executeWithMessage: executeDepositMessage
  } = useEigenLayerOperation({
    targetContractAddr: STRATEGY_MANAGER_ADDRESS,
    amount,
    tokenApproval: {
      tokenAddress: BaseSepolia.bridgeToken,
      spenderAddress: SENDER_CCIP_ADDRESS,
      amount
    },
    expiryMinutes: 45, // expiry for refunds on reverts, max is 3 days.
    onSuccess: (txHash, receipt) => {
      if (txHash && receipt) {
        addTransaction({
          txHash,
          messageId: "", // Server will extract the real messageId if needed
          timestamp: Math.floor(Date.now() / 1000),
          txType: 'deposit',
          status: 'confirmed',
          from: receipt.from,
          to: receipt.to || '',
          user: l1Wallet.account || '',
          isComplete: false,
          sourceChainId: BaseSepolia.chainId.toString(),
          destinationChainId: EthSepolia.chainId.toString()
        });
        showToast('Transaction recorded in history!', 'success');

        // Refresh strategy stats after successful deposit
        setTimeout(() => fetchStrategyStats(), 5000);
      }
      showToast(`Transaction sent! Hash: ${txHash}`, 'success');
    },
    onError: (err) => {
      console.error('Error in deposit operation:', err);
      showToast(`Error in deposit operation: ${err.message}`, 'error');
    },
    customGasLimit: gasLimit
  });

  // Show toast when error occurs
  useEffect(() => {
    if (error) {
      showToast(error, 'error');
    }
  }, [error, showToast]);

  // Handle deposit into strategy
  const handleDepositIntoStrategy = async () => {
    if (!transactionAmount) {
      showToast("Invalid transaction amount", 'error');
      return;
    }

    // Show signing notification
    showToast("Please sign the transaction in your wallet...", 'info');

    // Create the Eigenlayer depositIntoStrategy message
    const depositMessage = encodeDepositIntoStrategyMsg(
      STRATEGY,
      EthSepolia.bridgeToken,
      amount
    );

    // Execute with the message directly
    try {
      await executeDepositMessage(depositMessage);
    } catch (error) {
      console.error("Error depositing into strategy:", error);

      // If this contains 'rejected', it's likely a user cancellation
      const errorMessage = error instanceof Error ? error.message : String(error);
      if (errorMessage.toLowerCase().includes('rejected') ||
          errorMessage.toLowerCase().includes('denied') ||
          errorMessage.toLowerCase().includes('cancelled') ||
          errorMessage.toLowerCase().includes('user refused') ||
          errorMessage.toLowerCase().includes('declined')) {
        // It's a rejection - immediately reset all states
        console.log('Transaction rejected by user, resetting states...');
        showToast('Transaction was rejected by user', 'info');
      }
      // No need to show error toast here as it's already handled in onError callback
    }
  };

  // Format numbers for display
  const formatNumber = (value: bigint | null): string => {
    if (value === null) return 'Loading...';
    return parseFloat(formatEther(value)).toLocaleString(undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 6
    });
  };

  // Check if we should disable inputs
  const isInputDisabled = !isConnected || isExecuting;

  return (
    <div className="deposit-page">
      <div className="transaction-form">
        <h3>MAGIC Strategy Stats</h3>
        <div className="stats-grid">
          <div className="stat-item">
            <span className="stat-label">Total Shares:</span>
            {isLoadingStrategyStats ? (
              <div className="loading-container">
                <span className="loading-spinner"></span>
              </div>
            ) : (
              <span className="stat-value">{formatNumber(totalShares)}</span>
            )}
          </div>
          <div className="stat-item">
            <span className="stat-label">Total Staked MAGIC:</span>
            {isLoadingStrategyStats ? (
              <div className="loading-container">
                <span className="loading-spinner"></span>
              </div>
            ) : (
              <span className="stat-value">{formatNumber(totalStaked)}</span>
            )}
          </div>
          </div>
      </div>
      <div className="transaction-form">
        <h2>Deposit into Strategy</h2>

        {isFirstTimeUser && (
          <div className="info-banner first-time">
            <h3>First-time User</h3>
            <p>This transaction will mint a new EigenAgent for you and deposit funds into EigenLayer.</p>
            <p>It requires more gas (~860,000 gas limit) than future transactions.</p>
            <p>Predicted EigenAgent Address: {predictedEigenAgentAddress || 'Loading...'}</p>
          </div>
        )}

        {eigenAgentInfo && (
          <div className="info-banner existing-user">
            <h3>Existing User</h3>
            <p>Using your existing EigenAgent at {eigenAgentInfo.eigenAgentAddress}</p>
            <p>Current exec nonce: {eigenAgentInfo.execNonce.toString()}</p>
          </div>
        )}

        <div className="form-group">
          <label htmlFor="amount">Amount to deposit (MAGIC):</label>
          <input
            id="amount"
            type="text"
            value={transactionAmount}
            onChange={handleAmountChange}
            className="amount-input"
            placeholder="0.11"
            disabled={isInputDisabled}
          />
        </div>

        <button
          className="create-transaction-button"
          disabled={isInputDisabled || (!eigenAgentInfo?.eigenAgentAddress && !predictedEigenAgentAddress)}
          onClick={handleDepositIntoStrategy}
        >
          {isExecuting ? 'Processing...' : isFirstTimeUser ? 'Create EigenAgent & Deposit' : 'Sign Strategy Deposit'}
        </button>

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
      </div>
    </div>
  );
};

export default DepositPage;