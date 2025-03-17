import React, { useState, useEffect, useMemo } from 'react';
import { baseSepolia } from '../hooks/useClients';
import { formatEther, parseEther, Hex, Address } from 'viem';
import { encodeQueueWithdrawalMsg, encodeCompleteWithdrawalMsg, ZeroAddress, WithdrawalStruct } from '../utils/encoders';
import { CHAINLINK_CONSTANTS, STRATEGY_MANAGER_ADDRESS, STRATEGY, SENDER_CCIP_ADDRESS, DELEGATION_MANAGER_ADDRESS } from '../addresses';
import { useClientsContext } from '../contexts/ClientsContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { DelegationManagerABI } from '../abis';
import QueuedWithdrawals from './QueuedWithdrawals';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { useToast } from './ToastContainer';

// Extend the ProcessedWithdrawal interface from QueuedWithdrawals component
interface ProcessedWithdrawal {
  strategies: Address[];
  nonce: bigint;
  startBlock: bigint;
  withdrawer: Address;
  endBlock: bigint;
  canWithdrawAfter: string | null;
}

const WithdrawalPage: React.FC = () => {
  // Always call useTransactionHistory at the top level, even if you don't use it directly
  // This ensures consistent hook ordering because useEigenLayerOperation uses it internally
  const txHistory = useTransactionHistory();
  // Access toast notifications
  const { showToast } = useToast();

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
  const [withdrawalNonce, setWithdrawalNonce] = useState<bigint>(0n);
  const [delegatedTo, setDelegatedTo] = useState<Address | null>(null);
  const [isLoadingL1Data, setIsLoadingL1Data] = useState<boolean>(false);
  const [selectedWithdrawal, setSelectedWithdrawal] = useState<ProcessedWithdrawal | null>(null);
  const receiveAsTokens = true;
  const [isCompletingWithdrawal, setIsCompletingWithdrawal] = useState<boolean>(false);
  const [completeError, setCompleteError] = useState<string | null>(null);
  const [completeWithdrawalMessage, setCompleteWithdrawalMessage] = useState<Hex>("0x" as Hex);

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
        showToast(`Error fetching L1 data: ${err instanceof Error ? err.message : 'Unknown error'}`, 'error');
      } finally {
        setIsLoadingL1Data(false);
      }
    };

    fetchL1Data();
  }, [eigenAgentInfo, isConnected, l1Wallet.publicClient, showToast]);

  // Handle amount input changes with validation
  const handleAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    // Allow only valid number inputs (digits, one decimal point, and decimal digits)
    if (value === '' || /^(\d*\.?\d*)$/.test(value)) {
      setWithdrawalAmount(value);
    }
  };

  // Use the EigenLayer operation hook for queue withdrawal
  const {
    isExecuting: isQueueingWithdrawal,
    signature: queueSignature,
    error: queueError,
    isApprovingToken: isQueueApprovingToken,
    approvalHash: queueApprovalHash,
    executeWithMessage: executeQueueWithdrawalMessage
  } = useEigenLayerOperation({
    targetContractAddr: DELEGATION_MANAGER_ADDRESS,
    amount: 0n,
    expiryMinutes: 45,
    onSuccess: (txHash) => {
      showToast(`Withdrawal queued! Transaction hash: ${txHash}`, 'success');
    },
    onError: (err) => {
      console.error('Error in withdrawal operation:', err);
      showToast(`Error in withdrawal operation: ${err.message}`, 'error');
    }
  });

  // IMPORTANT: Always define this hook, regardless of whether completeWithdrawalMessage is set
  // This ensures consistent hook order between renders
  const {
    isExecuting: isExecutingComplete,
    error: completeHookError,
    executeWithMessage: executeCompleteWithdrawal
  } = useEigenLayerOperation({
    targetContractAddr: DELEGATION_MANAGER_ADDRESS,
    amount: 0n,
    expiryMinutes: 45,
    onSuccess: (txHash) => {
      showToast(`Withdrawal completed! Transaction hash: ${txHash}`, 'success');
      setSelectedWithdrawal(null);
      setIsCompletingWithdrawal(false);
    },
    onError: (err) => {
      console.error('Error in completing withdrawal:', err);
      setCompleteError(err.message);
      setIsCompletingWithdrawal(false);
    }
  });

  // Update the completeError state when completeHookError changes
  useEffect(() => {
    if (completeHookError) {
      setCompleteError(completeHookError);
      // Ensure the isCompletingWithdrawal state is reset when an error occurs
      setIsCompletingWithdrawal(false);

      // Display toast notification for the error
      showToast(completeHookError, 'error');
    }
  }, [completeHookError, showToast]);

  // Listen for error resets in the hook to keep our local state in sync
  useEffect(() => {
    // If the hook's error was cleared, also clear our local error
    if (!completeHookError && completeError) {
      setCompleteError(null);
    }
  }, [completeHookError, completeError]);

  // Show toast when queue error occurs
  useEffect(() => {
    if (queueError) {
      showToast(queueError, 'error');
    }
  }, [queueError, showToast]);

  // Handle completing a withdrawal
  const handleCompleteWithdrawal = async (withdrawal: ProcessedWithdrawal, sharesArray: bigint[]) => {
    if (!withdrawal) {
      showToast("No withdrawal selected", 'error');
      return;
    }

    if (!eigenAgentInfo || !delegatedTo) {
      showToast("EigenAgent info or delegated address not found", 'error');
      return;
    }

    try {
      setIsCompletingWithdrawal(true);
      setCompleteError(null);

      // Prepare the objects for the completeQueuedWithdrawal function
      const withdrawalStruct: WithdrawalStruct = {
        staker: eigenAgentInfo.eigenAgentAddress,
        delegatedTo: delegatedTo,
        withdrawer: eigenAgentInfo.eigenAgentAddress,
        nonce: withdrawal.nonce,
        startBlock: withdrawal.startBlock,
        strategies: withdrawal.strategies,
        scaledShares: sharesArray
      };

      // Create tokens to withdraw array (using strategy addresses)
      const tokensToWithdraw: Address[] = withdrawal.strategies;

      // Create the complete withdrawal message
      const message = encodeCompleteWithdrawalMsg(
        withdrawalStruct,
        tokensToWithdraw,
        receiveAsTokens
      );

      // Set the message and it will be used by the complete withdrawal hook
      setCompleteWithdrawalMessage(message);

      // Execute with the message directly
      await executeCompleteWithdrawal(message);
    } catch (error) {
      console.error("Error preparing complete withdrawal:", error);

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
      } else {
        // It's a different kind of error
        showToast(errorMessage, 'error');
      }

      setCompleteError(errorMessage);
      setIsCompletingWithdrawal(false);
    }
  };

  // Handle queueing withdrawal from strategy
  const handleQueueWithdrawal = async () => {
    if (!withdrawalAmount) {
      showToast("Please enter a valid withdrawal amount", 'error');
      return;
    }

    if (!eigenAgentInfo?.eigenAgentAddress) {
      showToast("No EigenAgent address found", 'error');
      return;
    }

    // Create the withdraw message with the encoded parameters
    const queueWithdrawalMessage = encodeQueueWithdrawalMsg(
      STRATEGY,
      amount,
      eigenAgentInfo.eigenAgentAddress
    );

    // Execute with the message directly
    try {
      await executeQueueWithdrawalMessage(queueWithdrawalMessage);
    } catch (error) {
      console.error("Error queueing withdrawal:", error);

      // No need to show toast here as it's already handled by onError callback
    }
  };

  // Check if we should disable inputs
  const isInputDisabled = !isConnected || isQueueingWithdrawal || isLoadingL1Data;

  return (
    <div className="transaction-form">
      <h2>Queue Withdrawal from Strategy</h2>

      <div className="withdrawal-info">
        <p>
          Queue a withdrawal to start the withdrawal process. After queueing,
          you'll need to wait for the unbonding period to complete before you can complete the withdrawal.
        </p>
        <p>
          The unbonding period is typically 7 days for EigenLayer strategies.
        </p>
      </div>

      <div className="form-group">
      </div>

      {isConnected && eigenAgentInfo && (
        <div className="form-group">
          <label>Withdrawal Information:</label>
          <div className="info-item">
            <strong>Target Address:</strong> {DELEGATION_MANAGER_ADDRESS}
            <div className="input-note">Using DelegationManager for Queue Withdrawals</div>
          </div>
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
          <div className="info-item">
            <strong>Transaction Expiry:</strong> 45 minutes from signing
          </div>
        </div>
      )}

      <div className="form-group">
        <label htmlFor="amount">Amount to withdraw (MAGIC):</label>
        <input
          id="amount"
          type="text"
          value={withdrawalAmount}
          onChange={handleAmountChange}
          className="amount-input"
          placeholder="0.05"
          disabled={isInputDisabled}
        />
        <button
          className="create-transaction-button"
          disabled={isInputDisabled || !eigenAgentInfo}
          onClick={handleQueueWithdrawal}
        >
          {isQueueingWithdrawal ? 'Processing...' : isLoadingL1Data ? 'Loading L1 Data...' : 'Queue Withdrawal'}
        </button>
      </div>

      <div className="withdrawals-section">
        <QueuedWithdrawals
          onSelectWithdrawal={handleCompleteWithdrawal}
          isCompletingWithdrawal={isCompletingWithdrawal}
        />
      </div>
    </div>
  );
};

export default WithdrawalPage;

