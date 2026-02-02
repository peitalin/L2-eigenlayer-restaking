import React, { useState, useEffect, useMemo, useRef } from 'react';
import { parseEther, Address, formatEther } from 'viem';
import { encodeQueueWithdrawalMsg, encodeCompleteWithdrawalMsg, WithdrawalStruct } from '../utils/encoders';
import { STRATEGY, DELEGATION_MANAGER_ADDRESS } from '../addresses';
import { EthSepolia, BaseSepolia } from '../addresses';
import { DelegationManagerABI } from '../abis';

import { useClientsContext } from '../contexts/ClientsContext';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { useToast } from '../utils/toast';
import UserDeposits, { UserDeposit } from '../components/UserDeposits';
import Expandable from '../components/Expandable';
import QueuedWithdrawals from '../components/QueuedWithdrawals';
import TransactionSuccessModal from '../components/TransactionSuccessModal';
import { simulateQueueWithdrawal, simulateCompleteWithdrawal, simulateOnEigenlayer } from '../utils/simulation';



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
    fetchEigenAgentInfo,
    predictedEigenAgentAddress
  } = useClientsContext();

  // State for transaction details
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [withdrawalAmount, setWithdrawalAmount] = useState<string>('0.05');
  const [withdrawalNonce, setWithdrawalNonce] = useState<bigint>(0n);
  const [delegatedTo, setDelegatedTo] = useState<Address | null>(null);
  const [isLoadingL1Data, setIsLoadingL1Data] = useState<boolean>(false);
  const receiveAsTokens = true;
  const [isCompletingWithdrawal, setIsCompletingWithdrawal] = useState<boolean>(false);
  const [completeError, setCompleteError] = useState<string | null>(null);
  const [userDeposits, setUserDeposits] = useState<UserDeposit[]>([]);

  // Add state for success modal
  const [showSuccessModal, setShowSuccessModal] = useState(false);
  const [successData, setSuccessData] = useState<{
    txHash: string;
    messageId: string;
    operationType: 'withdrawal';
    isLoading: boolean;
    simulationSuccess?: boolean;
  } | null>(null);

  // Use a ref to track if the modal is currently showing
  const modalVisibleRef = useRef(false);

  // Update the ref when the modal visibility changes
  useEffect(() => {
    modalVisibleRef.current = showSuccessModal;
  }, [showSuccessModal]);

  // Handler for when deposits are loaded from the UserDeposits component
  const handleDepositsLoaded = (deposits: UserDeposit[]) => {
    setUserDeposits(deposits);
  };

  // Handler for the Max button click
  const handleMaxButtonClick = () => {
    // Find the deposit for the MAGIC strategy
    const magicDeposit = userDeposits.find(
      deposit => deposit.strategy.toLowerCase() === STRATEGY.toLowerCase()
    );

    if (magicDeposit && magicDeposit.shares > 0n) {
      // Format the bigint shares to a string with appropriate decimal places
      const formattedAmount = formatEther(magicDeposit.shares);
      setWithdrawalAmount(formattedAmount);
      showToast('Max amount set', 'info');
    } else {
      showToast('No MAGIC deposits found', 'warning');
    }
  };

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
    // Fetch L1 data needed for withdrawal - with debouncing
    // Skip if conditions aren't met or if we're already loading
    if (!isConnected || !eigenAgentInfo || !l1Wallet.publicClient || isLoadingL1Data) {
      return;
    }

    // Use a timer to debounce rapid fetchL1Data calls
    const timer = setTimeout(() => {
      const fetchL1Data = async () => {
        try {
          setIsLoadingL1Data(true);

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
    customGasLimit: 580_000n, // see GasLimits.sol
    onSuccess: (txHash, receipt, execNonce) => {
      if (txHash && receipt) {
        addTransaction({
          txHash,
          messageId: "",
          timestamp: Math.floor(Date.now() / 1000),
          txType: 'queueWithdrawal',
          status: 'confirmed',
          from: receipt.from,
          to: receipt.to || '',
          user: l1Wallet.account || '',
          isComplete: false,
          sourceChainId: BaseSepolia.chainId.toString(),
          destinationChainId: EthSepolia.chainId.toString(),
          execNonce: execNonce
        });

        // Update modal to show confirmed state
        setSuccessData(prev => prev ? {
          ...prev,
          isLoading: false,
          messageId: "" // Update if messageId becomes available
        } : null);

        showToast('Transaction recorded in history!', 'success');

        // Auto-close modal after 5 seconds
        setTimeout(() => {
          setShowSuccessModal(false);
          setSuccessData(null);
        }, 5000);
      }
      showToast(`Withdrawal queued! Transaction hash: ${txHash}`, 'success');
    },
    onError: (error: Error) => {
      console.error('Error in withdrawal operation:', error);

      // Check if it's a user rejection
      const errorMessage = error.message.toLowerCase();
      if (errorMessage.includes('rejected') ||
          errorMessage.includes('denied') ||
          errorMessage.includes('cancelled') ||
          errorMessage.includes('user refused') ||
          errorMessage.includes('declined')) {
        showToast('Transaction was cancelled', 'info');
      } else {
        showToast(`Error in withdrawal operation: ${error.message}`, 'error');
      }

      // Clear modal state
      setSuccessData(null);
      setShowSuccessModal(false);
    },
  });

  const {
    isExecuting: isExecutingComplete,
    error: completeHookError,
    executeWithMessage: executeCompleteWithdrawal
  } = useEigenLayerOperation({
    targetContractAddr: DELEGATION_MANAGER_ADDRESS,
    amount: 0n,
    expiryMinutes: 45,
    customGasLimit: 630_000n, // see GasLimits.sol
    onSuccess: (txHash, receipt, execNonce) => {
      if (txHash && receipt) {
        addTransaction({
          txHash,
          messageId: "",
          timestamp: Math.floor(Date.now() / 1000),
          txType: 'completeWithdrawal',
          status: 'confirmed',
          from: receipt.from,
          to: receipt.to || '',
          user: l1Wallet.account || '',
          isComplete: false,
          sourceChainId: BaseSepolia.chainId.toString(),
          destinationChainId: EthSepolia.chainId.toString(),
          execNonce: execNonce
        });

        // Update modal to show confirmed state
        setSuccessData(prev => prev ? {
          ...prev,
          isLoading: false,
          messageId: "" // Update if messageId becomes available
        } : null);

        showToast('Transaction recorded in history!', 'success');

        // Auto-close modal after 5 seconds
        setTimeout(() => {
          setShowSuccessModal(false);
          setSuccessData(null);
        }, 5000);

        setIsCompletingWithdrawal(false);
      }
      showToast(`Withdrawal completed! Transaction hash: ${txHash}`, 'success');
    },
    onError: (error: Error) => {
      console.error('Error in completing withdrawal:', error);

      // Check if it's a user rejection
      const errorMessage = error.message.toLowerCase();
      if (errorMessage.includes('rejected') ||
          errorMessage.includes('denied') ||
          errorMessage.includes('cancelled') ||
          errorMessage.includes('user refused') ||
          errorMessage.includes('declined')) {
        showToast('Transaction was cancelled', 'info');
      } else {
        showToast(`Error in completing withdrawal: ${error.message}`, 'error');
      }

      // Clear modal state
      setSuccessData(null);
      setShowSuccessModal(false);

      setCompleteError(error.message);
      setIsCompletingWithdrawal(false);
    },
  });

  // Update the completeError state when completeHookError changes
  useEffect(() => {
    if (completeHookError) {
      // Handle both string and Error types
      const errorMessage = typeof completeHookError === 'string'
        ? completeHookError
        : (completeHookError as Error).message;
      setCompleteError(errorMessage);
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
  const handleCompleteWithdrawal = async (withdrawal: WithdrawalStruct, sharesArray: bigint[]) => {
    if (!withdrawal) {
      showToast("No withdrawal selected", 'error');
      return;
    }

    if (!eigenAgentInfo) {
      showToast("EigenAgent info or delegated address not found", 'error');
      return;
    }

    if (!l1Wallet.account || !l1Wallet.publicClient) {
      showToast("Wallet not connected", 'error');
      return;
    }

    // Show the modal with loading state first
    const initialModalData = {
      txHash: '',
      messageId: '',
      operationType: 'withdrawal' as const,
      isLoading: true,
      simulationSuccess: undefined
    };
    setSuccessData(initialModalData);
    setShowSuccessModal(true);

    try {
      setIsCompletingWithdrawal(true);
      setCompleteError(null);

      // Prepare the objects for the completeQueuedWithdrawal function
      const withdrawalStruct: WithdrawalStruct = {
        ...withdrawal,
        scaledShares: sharesArray
      };

      // Create tokens to withdraw array (tokens, not strategies)
      const tokensToWithdraw: Address[] = [EthSepolia.bridgeToken as Address];

      // Run L1 simulation with chain switching handled by wrapper
      await simulateOnEigenlayer({
        simulate: () => simulateCompleteWithdrawal(
          withdrawalStruct,
          tokensToWithdraw,
          receiveAsTokens,
          eigenAgentInfo.eigenAgentAddress
        ),
        switchChain,
        onSuccess: () => {
          console.log("Withdrawal completion simulation successful");
          showToast('Withdrawal completion simulation successful', 'success');
          // Update modal with simulation success
          if (modalVisibleRef.current) {
            setSuccessData(prev => prev ? {
              ...prev,
              simulationSuccess: true
            } : null);
          }
        },
        onError: (error: string) => {
          console.error('Complete withdrawal simulation failed:', error);
          showToast(`Withdrawal completion may fail: ${error}`, 'error');
          // Update modal with simulation failure
          if (modalVisibleRef.current && successData) {
            setSuccessData({
              ...successData,
              simulationSuccess: false
            });
          }
          throw new Error(error); // Convert string error to Error object
        }
      });

      // Create the complete withdrawal message
      const message = encodeCompleteWithdrawalMsg(
        withdrawalStruct,
        tokensToWithdraw,
        receiveAsTokens
      );

      // Execute with the message directly
      const result = await executeCompleteWithdrawal(message);

      // Update modal with transaction hash when available
      if (result?.txHash) {
        setSuccessData(prev => ({
          ...prev!,
          txHash: result.txHash
        }));
      }
    } catch (error) {
      console.error("Error preparing complete withdrawal:", error);

      // If this contains 'rejected', it's likely a user cancellation
      const errorMessage = error instanceof Error ? error.message : String(error);
      if (errorMessage.toLowerCase().includes('rejected') ||
          errorMessage.toLowerCase().includes('denied') ||
          errorMessage.toLowerCase().includes('cancelled') ||
          errorMessage.toLowerCase().includes('user refused') ||
          errorMessage.toLowerCase().includes('declined')) {
        console.log('Transaction rejected by user, resetting states...');
        showToast('Transaction was rejected by user', 'info');
      } else {
        showToast(errorMessage, 'error');
      }

      setCompleteError(errorMessage);
      setIsCompletingWithdrawal(false);
      // Clear modal on any error
      setSuccessData(null);
      setShowSuccessModal(false);
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

    if (!l2Wallet.account || !l2Wallet.publicClient) {
      showToast("Wallet not connected", 'error');
      return;
    }

    try {
      setIsLoading(true);

      // Show the modal with loading state first
      const initialModalData = {
        txHash: '',
        messageId: '',
        operationType: 'withdrawal' as const,
        isLoading: true,
        simulationSuccess: undefined
      };
      setSuccessData(initialModalData);
      setShowSuccessModal(true);

      // Run simulation with chain switching handled by wrapper
      await simulateOnEigenlayer({
        simulate: () => simulateQueueWithdrawal(
          STRATEGY as Address,
          amount,
          eigenAgentInfo.eigenAgentAddress
        ),
        switchChain,
        onSuccess: () => {
          console.log("Queue withdrawal simulation successful!");
          showToast("Queue withdrawal simulation successful!", "success");
          // Update modal with simulation success
          if (modalVisibleRef.current) {
            setSuccessData(prev => prev ? {
              ...prev,
              simulationSuccess: true
            } : null);
          }
        },
        onError: (error: string) => {
          console.error("Queue withdrawal simulation failed:", error);
          showToast(`Queue withdrawal simulation failed: ${error}`, "error");
          // Update modal with simulation failure
          if (modalVisibleRef.current && successData) {
            setSuccessData({
              ...successData,
              simulationSuccess: false
            });
          }
          setIsLoading(false);
          throw new Error(error); // Throw to prevent continuing with the withdrawal
        }
      });

      // Create the withdraw message with the encoded parameters
      const queueWithdrawalMessage = encodeQueueWithdrawalMsg(
        STRATEGY,
        amount,
        eigenAgentInfo.eigenAgentAddress
      );

      // Execute the withdrawal operation
      await executeQueueWithdrawalMessage(queueWithdrawalMessage);

    } catch (err) {
      console.error('Error during queue withdrawal:', err);
      setError(`Queue withdrawal error: ${err instanceof Error ? err.message : String(err)}`);
      setIsLoading(false);
    }
  };

  // Check if we should disable inputs
  const isInputDisabled = !isConnected || isQueueingWithdrawal || isLoadingL1Data;

  return (
    <div className="treasure-page-container">

      <div className="treasure-header">
        <div className="treasure-title">
          <span>Withdraw</span>
        </div>
      </div>

      {/* Top section: Queued Withdrawals */}
      <QueuedWithdrawals
        onSelectWithdrawal={handleCompleteWithdrawal}
        isCompletingWithdrawal={isCompletingWithdrawal}
      />

      {/* Bottom section: Withdraw from Strategy */}
      <div className="treasure-card">
        <div className="treasure-card-header">
          <div className="treasure-card-title">Withdraw from Strategy</div>
        </div>

        {/* Display user deposits */}
        <UserDeposits onDepositsLoaded={handleDepositsLoaded} />

        <div className="treasure-stat-label">
          <label htmlFor="amount">
            Amount to withdraw (MAGIC)
          </label>
        </div>
        <div className="treasure-input-container">
          <input
            id="amount"
            className="treasure-input"
            type="text"
            value={withdrawalAmount}
            onChange={handleAmountChange}
            placeholder="0.05"
            disabled={isInputDisabled}
          />
          <button
            className="treasure-max-button"
            onClick={handleMaxButtonClick}
            disabled={isInputDisabled || userDeposits.length === 0}
          >
            Max
          </button>
        </div>

        <button
          className="treasure-action-button"
          disabled={isInputDisabled || !eigenAgentInfo}
          onClick={handleQueueWithdrawal}
          style={{ width: '100%', marginTop: '16px' }}
        >
          {isQueueingWithdrawal ? (
            <>
              <span className="loading-spinner"></span>
              <span>Processing...</span>
            </>
          ) : isLoadingL1Data ? (
            <>
              <span className="loading-spinner"></span>
              <span>Loading L1 Data...</span>
            </>
          ) : (
            'Queue Withdrawal'
          )}
        </button>

        <div className="treasure-info-section" style={{ marginTop: '24px' }}>
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
            <div className="treasure-info-section">
              <div className="treasure-info-item">
                <span className="treasure-info-label">Target Address:</span>
                <span className="treasure-info-value font-mono">{DELEGATION_MANAGER_ADDRESS}</span>
                <div className="input-note">Using DelegationManager for Queue Withdrawals</div>
              </div>
              <div className="treasure-info-item">
                <span className="treasure-info-label">Current Withdrawal Nonce:</span>
                {isLoadingL1Data ? (
                  <span className="treasure-info-value">
                    <span className="loading-spinner spinner-small"></span>
                    Loading...
                  </span>
                ) : (
                  <span className="treasure-info-value">{withdrawalNonce.toString()}</span>
                )}
              </div>
              <div className="treasure-info-item">
                <span className="treasure-info-label">Delegated To:</span>
                {isLoadingL1Data ? (
                  <span className="treasure-info-value">
                    <span className="loading-spinner spinner-small"></span>
                    Loading...
                  </span>
                ) : (
                  <span className="treasure-info-value font-mono">
                    {delegatedTo ? delegatedTo : 'Not delegated'}
                  </span>
                )}
              </div>
              <div className="treasure-info-item">
                <span className="treasure-info-label">Withdrawer Address:</span>
                <span className="treasure-info-value font-mono">{eigenAgentInfo.eigenAgentAddress}</span>
                <div className="input-note">Your EigenAgent will be set as the withdrawer</div>
              </div>
              <div className="treasure-info-item">
                <span className="treasure-info-label">Transaction Expiry:</span>
                <span className="treasure-info-value">45 minutes from signing</span>
              </div>
            </div>
          </Expandable>
        )}
      </div>

      {/* Transaction Success Modal */}
      {successData && (
        <TransactionSuccessModal
          isOpen={showSuccessModal}
          onClose={() => {
            setShowSuccessModal(false);
            setSuccessData(null);
          }}
          txHash={successData.txHash}
          messageId={successData.messageId}
          operationType={successData.operationType}
          sourceChainId={BaseSepolia.chainId.toString()}
          destinationChainId={EthSepolia.chainId.toString()}
          isLoading={successData.isLoading}
          simulationSuccess={successData.simulationSuccess}
        />
      )}
    </div>
  );
};

export default WithdrawalPage;