import React, { useState, useEffect, useMemo } from 'react';
import { parseEther, Address } from 'viem';
import { encodeQueueWithdrawalMsg, encodeCompleteWithdrawalMsg, WithdrawalStruct } from '../utils/encoders';
import { STRATEGY, DELEGATION_MANAGER_ADDRESS } from '../addresses';
import { EthSepolia, BaseSepolia } from '../addresses';
import { DelegationManagerABI } from '../abis';

import { useClientsContext } from '../contexts/ClientsContext';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { useToast } from '../utils/toast';
import UserDeposits from '../components/UserDeposits';
import Expandable from '../components/Expandable';
import QueuedWithdrawals from '../components/QueuedWithdrawals';

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
  const { addTransaction } = useTransactionHistory();
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
  const receiveAsTokens = true;
  const [isCompletingWithdrawal, setIsCompletingWithdrawal] = useState<boolean>(false);
  const [completeError, setCompleteError] = useState<string | null>(null);

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
    // Only fetch if not already loading and not already fetched
    if (l1Wallet.account && !eigenAgentInfo && isConnected && !isLoadingEigenAgent) {
      fetchEigenAgentInfo();
    }
    // Don't include eigenAgentInfo in deps to avoid refetching when it changes
  }, [l1Wallet.account, isConnected, isLoadingEigenAgent, fetchEigenAgentInfo]);

  // Fetch L1 data needed for withdrawal - with debouncing
  useEffect(() => {
    // Skip if conditions aren't met or if we're already loading
    if (!isConnected || !eigenAgentInfo || !l1Wallet.publicClient || isLoadingL1Data) {
      return;
    }

    // Use a timer to debounce rapid fetchL1Data calls
    const timer = setTimeout(() => {
      const fetchL1Data = async () => {
        try {
          setIsLoadingL1Data(true);

          // Get both values in parallel to reduce API calls
          const [nonce, delegated] = await Promise.all([
            l1Wallet.publicClient.readContract({
              address: DELEGATION_MANAGER_ADDRESS,
              abi: DelegationManagerABI,
              functionName: 'cumulativeWithdrawalsQueued',
              args: [eigenAgentInfo.eigenAgentAddress]
            }),
            l1Wallet.publicClient.readContract({
              address: DELEGATION_MANAGER_ADDRESS,
              abi: DelegationManagerABI,
              functionName: 'delegatedTo',
              args: [eigenAgentInfo.eigenAgentAddress]
            })
          ]);

          setWithdrawalNonce(nonce as bigint);
          setDelegatedTo(delegated as Address);
        } catch (err) {
          console.error('Error fetching L1 data:', err);
        } finally {
          setIsLoadingL1Data(false);
        }
      };

      fetchL1Data();
    }, 500); // Debounce for 500ms

    return () => clearTimeout(timer);
  }, [eigenAgentInfo, isConnected, l1Wallet.publicClient]);

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
    info,
    isApprovingToken: isQueueApprovingToken,
    approvalHash: queueApprovalHash,
    executeWithMessage: executeQueueWithdrawalMessage,
  } = useEigenLayerOperation({
    targetContractAddr: DELEGATION_MANAGER_ADDRESS,
    amount: 0n,
    expiryMinutes: 45,
    onSuccess: (txHash, receipt) => {
      if (txHash && receipt) {
        addTransaction({
          txHash,
          messageId: "", // Server will extract the real messageId if needed
          timestamp: Math.floor(Date.now() / 1000),
          txType: 'queueWithdrawal',
          status: 'confirmed',
          from: receipt.from,
          to: receipt.to || '',
          user: l1Wallet.account || '',
          isComplete: false,
          sourceChainId: BaseSepolia.chainId.toString(),
          destinationChainId: EthSepolia.chainId.toString()
        });
      }
      showToast(`Withdrawal queued! Transaction hash: ${txHash}`, 'success');
    },
    onError: (err) => {
      console.error('Error in withdrawal operation:', err);
      showToast(`Error in withdrawal operation: ${err.message}`, 'error');
    },
    customGasLimit: 580_000n // see GasLimits.sol
  });

  const {
    isExecuting: isExecutingComplete,
    error: completeHookError,
    executeWithMessage: executeCompleteWithdrawal
  } = useEigenLayerOperation({
    targetContractAddr: DELEGATION_MANAGER_ADDRESS,
    amount: 0n,
    expiryMinutes: 45,
    onSuccess: (txHash, receipt) => {
      if (txHash && receipt) {
        addTransaction({
          txHash,
          messageId: "", // Server will extract the real messageId if needed
          timestamp: Math.floor(Date.now() / 1000),
          txType: 'completeWithdrawal',
          status: 'confirmed',
          from: receipt.from,
          to: receipt.to || '',
          user: l1Wallet.account || '',
          isComplete: false,
          sourceChainId: BaseSepolia.chainId.toString(),
          destinationChainId: EthSepolia.chainId.toString()
        });
      }
      showToast(`Withdrawal completed! Transaction hash: ${txHash}`, 'success');
      setIsCompletingWithdrawal(false);
    },
    onError: (err) => {
      console.error('Error in completing withdrawal:', err);
      setCompleteError(err.message);
      setIsCompletingWithdrawal(false);
    },
    customGasLimit: 630_000n // see GasLimits.sol
  });

  // Update the completeError state when completeHookError changes
  useEffect(() => {
    if (completeHookError) {
      setCompleteError(completeHookError);
      // Ensure the isCompletingWithdrawal state is reset when an error occurs
      setIsCompletingWithdrawal(false);
    }
  }, [completeHookError, showToast]);

  // Listen for error resets in the hook to keep our local state in sync
  useEffect(() => {
    // If the hook's error was cleared, also clear our local error
    if (!completeHookError && completeError) {
      setCompleteError(null);
    }
  }, [completeHookError, completeError]);

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

      // Show a signing notification
      showToast("Please sign the transaction in your wallet...", 'info');

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

      // Create tokens to withdraw array (tokens, not strategies)
      const tokensToWithdraw: Address[] = [EthSepolia.bridgeToken as Address];

      // Create the complete withdrawal message
      const message = encodeCompleteWithdrawalMsg(
        withdrawalStruct,
        tokensToWithdraw,
        receiveAsTokens
      );

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

    // Show a signing notification
    showToast("Please sign the transaction in your wallet...", 'info');

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
    <div className="withdrawal-page-layout">
      {/* Top section: Queued Withdrawals */}
      <div className="transaction-form">
        <h2>Queued Withdrawals</h2>
        <QueuedWithdrawals
          onSelectWithdrawal={handleCompleteWithdrawal}
          isCompletingWithdrawal={isCompletingWithdrawal}
        />
      </div>

      {/* Bottom section: Withdraw from Strategy */}
      <div className="transaction-form">
        <h2>Withdraw from Strategy</h2>

        {/* Display user deposits */}
        <UserDeposits />

        <div className="form-group">
          <label htmlFor="amount">Amount to withdraw (MAGIC)</label>
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

        <div className="withdrawal-info">
          <p>
            Queue a withdrawal to start the withdrawal process. After queueing,
            you'll need to wait for the unbonding period to complete before you can complete the withdrawal.
          </p>
          <p>
            The unbonding period is typically 7 days for EigenLayer strategies.
          </p>
        </div>

        {isConnected && eigenAgentInfo && (
          <Expandable title="Withdrawal Details" initialExpanded={false}>
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
          </Expandable>
        )}

      </div>
    </div>
  );
};

export default WithdrawalPage;
