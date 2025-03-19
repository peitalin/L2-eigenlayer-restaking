import React, { useState, useEffect, useMemo } from 'react';
import { formatEther, parseEther } from 'viem';
import { encodeDepositIntoStrategyMsg } from '../utils/encoders';
import { CHAINLINK_CONSTANTS, STRATEGY_MANAGER_ADDRESS, STRATEGY, SENDER_CCIP_ADDRESS, REWARDS_COORDINATOR_ADDRESS } from '../addresses';
import { useClientsContext } from '../contexts/ClientsContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { useToast } from '../utils/toast';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';


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
    fetchEigenAgentInfo
  } = useClientsContext();
  const { showToast } = useToast();

  // State for transaction details
  const [transactionAmount, setTransactionAmount] = useState<string>('0.11');
  const { addTransaction } = useTransactionHistory();

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

  // Add a useEffect that will run once when the component mounts
  useEffect(() => {
    // Check if we already have the l1Account and still need to fetch eigenAgentInfo
    // Only fetch if not already loading and not already fetched
    if (l1Wallet.account && !eigenAgentInfo && isConnected && !isLoadingEigenAgent) {
      fetchEigenAgentInfo();
    }
    // Don't include eigenAgentInfo in deps to avoid refetching when it changes
  }, [l1Wallet.account, isConnected, isLoadingEigenAgent, fetchEigenAgentInfo]);

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
      tokenAddress: CHAINLINK_CONSTANTS.baseSepolia.bridgeToken,
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
          sourceChainId: CHAINLINK_CONSTANTS.baseSepolia.chainId.toString(),
          destinationChainId: CHAINLINK_CONSTANTS.ethSepolia.chainId.toString()
        });
        showToast('Transaction recorded in history!', 'success');
      }
      showToast(`Transaction sent! Hash: ${txHash}`, 'success');
    },
    onError: (err) => {
      console.error('Error in deposit operation:', err);
      showToast(`Error in deposit operation: ${err.message}`, 'error');
    }
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
      CHAINLINK_CONSTANTS.ethSepolia.bridgeToken,
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

  // Check if we should disable inputs
  const isInputDisabled = !isConnected || isExecuting;

  return (
    <div className="transaction-form">
      <h2>Deposit into Strategy</h2>

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
        <div className="input-note">Using StrategyManager from EigenLayer contracts</div>
      </div>

      <div className="form-group">
        <label htmlFor="amount">Token Amount:</label>
        <input
          id="amount"
          type="text"
          value={transactionAmount}
          onChange={handleAmountChange}
          className="amount-input"
          placeholder="0.11"
          disabled={isInputDisabled}
        />
        <div className="input-note">Using EigenLayer TokenERC20</div>
      </div>

      <div className="form-group">
        <label>Transaction Expiry:</label>
        <div className="info-item">
          45 minutes from signing
        </div>
      </div>

      <button
        className="create-transaction-button"
        disabled={isInputDisabled || !eigenAgentInfo?.eigenAgentAddress}
        onClick={handleDepositIntoStrategy}
      >
        {isExecuting ? 'Processing...' : 'Sign Strategy Deposit'}
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
  );
};

export default DepositPage;