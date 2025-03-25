import React, { useState, useEffect, useMemo, useRef } from 'react';
import { formatEther, parseEther, Address } from 'viem';
import { encodeDepositIntoStrategyMsg } from '../utils/encoders';
import { STRATEGY_MANAGER_ADDRESS, STRATEGY, SENDER_CCIP_ADDRESS } from '../addresses';
import { BaseSepolia, EthSepolia } from '../addresses';
import { useClientsContext } from '../contexts/ClientsContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { useToast } from '../utils/toast';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { publicClients } from '../hooks/useClients';
import { EXPLORER_URLS } from '../configs';
import TransactionSuccessModal from '../components/TransactionSuccessModal';
import { simulateDepositIntoStrategy, simulateOnEigenlayer } from '../utils/simulation';

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

// Add the ERC20 ABI for the functions we need
const erc20Abi = [
  {
    name: 'balanceOf',
    type: 'function',
    inputs: [{ type: 'address', name: 'account' }],
    outputs: [{ type: 'uint256' }],
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

  // State for loading
  const [isLoading, setIsLoading] = useState(false);

  // State for transaction details
  const [transactionAmount, setTransactionAmount] = useState<string>('0.11');
  const { addTransaction } = useTransactionHistory();

  // State for strategy stats
  const [totalShares, setTotalShares] = useState<bigint | null>(null);
  const [totalStaked, setTotalStaked] = useState<bigint | null>(null);
  const [isLoadingStrategyStats, setIsLoadingStrategyStats] = useState(false);

  // Add state for token balance
  const [tokenBalance, setTokenBalance] = useState<bigint | null>(null);
  const [isLoadingTokenBalance, setIsLoadingTokenBalance] = useState(false);

  // Add state for success modal
  const [showSuccessModal, setShowSuccessModal] = useState(false);
  const [successData, setSuccessData] = useState<{
    txHash: string;
    messageId: string;
    operationType: 'deposit';
    isLoading: boolean;
    simulationSuccess?: boolean;
  } | null>(null);

  // Use a ref to track if the modal is currently showing
  const modalVisibleRef = useRef(false);

  // Update the ref when the modal visibility changes
  useEffect(() => {
    modalVisibleRef.current = showSuccessModal;
  }, [showSuccessModal]);

  // Handle closing the success modal
  const handleCloseSuccessModal = () => {
    setShowSuccessModal(false);
    setSuccessData(null);
  };

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

  // Function to fetch token balance
  const fetchTokenBalance = async () => {
    if (!l2Wallet.account || !l2Wallet.publicClient) return;

    setIsLoadingTokenBalance(true);
    try {
      const balance = await l2Wallet.publicClient.readContract({
        address: BaseSepolia.bridgeToken,
        abi: erc20Abi,
        functionName: 'balanceOf',
        args: [l2Wallet.account]
      }) as bigint;

      setTokenBalance(balance);
    } catch (error) {
      console.error('Error fetching token balance:', error);
      showToast('Failed to load token balance', 'error');
    } finally {
      setIsLoadingTokenBalance(false);
    }
  };

  useEffect(() => {
    // Fetch strategy stats when component mounts
    fetchStrategyStats();
  }, []);

  // Fetch token balance when account changes or after successful deposit
  useEffect(() => {
    if (l2Wallet.account) {
      fetchTokenBalance();
    } else {
      setTokenBalance(null);
    }
  }, [l2Wallet.account]);

  // Handle amount input changes with validation
  const handleAmountChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value;
    // Allow only valid number inputs (digits, one decimal point, and decimal digits)
    if (value === '' || /^(\d*\.?\d*)$/.test(value)) {
      setTransactionAmount(value);
    }
  };

  // Handle Max button click
  const handleMaxButtonClick = () => {
    if (tokenBalance && tokenBalance > 0n) {
      // Format the bigint balance to a string with appropriate decimal places
      const formattedAmount = formatEther(tokenBalance);
      setTransactionAmount(formattedAmount);
      showToast('Max amount set', 'info');
    } else {
      showToast('No MAGIC tokens available', 'warning');
    }
  };

  // Handle deposit into strategy
  const handleDepositIntoStrategy = async () => {
    if (!transactionAmount) {
      showToast("Invalid transaction amount", 'error');
      return;
    }

    if (!l2Wallet.client || !l2Wallet.account || !l2Wallet.publicClient) {
      showToast("Wallet not connected", 'error');
      return;
    }

    // Determine the staker address (eigenAgent or predicted address for first-time users)
    const stakerAddress = eigenAgentInfo?.eigenAgentAddress ||
                          (predictedEigenAgentAddress as Address);

    if (!stakerAddress) {
      showToast("Cannot determine EigenAgent address", 'error');
      return;
    }

    try {
      setIsLoading(true);

      // Show the modal with loading state first
      const initialModalData = {
        txHash: '',
        messageId: '',
        operationType: 'deposit' as const,
        isLoading: true,
        simulationSuccess: undefined
      };
      setSuccessData(initialModalData);
      setShowSuccessModal(true);

      // Run simulation with chain switching handled by wrapper
      await simulateOnEigenlayer({
        simulate: () => simulateDepositIntoStrategy(
          STRATEGY as Address,
          EthSepolia.bridgeToken,
          amount,
          stakerAddress
        ),
        switchChain,
        onSuccess: () => {
          console.log("Deposit simulation successful!");
          showToast("Deposit simulation successful!", "success");
          // Update modal with simulation success
          if (modalVisibleRef.current) {
            setSuccessData(prev => prev ? {
              ...prev,
              simulationSuccess: true
            } : null);
          }
        },
        onError: (error: string) => {
          console.error("Deposit simulation failed:", error);
          showToast(`Deposit simulation failed: ${error}`, "error");
          // Close modal on simulation failure
          setShowSuccessModal(false);
          setSuccessData(null);
          setIsLoading(false);
          throw new Error(error); // Throw to prevent continuing with the deposit
        }
      });

      // Create the Eigenlayer depositIntoStrategy message
      const depositMessage = encodeDepositIntoStrategyMsg(
        STRATEGY,
        EthSepolia.bridgeToken,
        amount
      );

      // Execute with the message directly
      const result = await executeDepositMessage(depositMessage);

      // Update modal with transaction hash when available
      if (result?.txHash) {
        setSuccessData(prev => prev ? {
          ...prev,
          txHash: result.txHash,
          isLoading: false
        } : null);
      }
    } catch (error) {
      console.error("Error depositing into strategy:", error);

      // If this contains 'rejected', it's likely a user cancellation
      const errorMessage = error instanceof Error ? error.message : String(error);
      if (errorMessage.toLowerCase().includes('rejected') ||
          errorMessage.toLowerCase().includes('denied') ||
          errorMessage.toLowerCase().includes('cancelled') ||
          errorMessage.toLowerCase().includes('user refused') ||
          errorMessage.toLowerCase().includes('declined')) {
        // It's a rejection - show info toast
        console.log('Transaction rejected by user');
        showToast('Transaction was rejected by user', 'info');
      } else {
        showToast(errorMessage, 'error');
      }

      // Close modal on any error
      setShowSuccessModal(false);
      setSuccessData(null);
    } finally {
      setIsLoading(false);
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
    expiryMinutes: 45,
    customGasLimit: gasLimit,
    onSuccess: (txHash, receipt, execNonce) => {
      if (txHash && receipt) {
        // Add transaction to history
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
          destinationChainId: EthSepolia.chainId.toString(),
          execNonce: execNonce
        });

        // Update modal to show confirmed state while preserving simulation status
        if (modalVisibleRef.current) {
          setSuccessData(prev => prev ? {
            ...prev,
            isLoading: false,
            txHash: txHash,
            messageId: "" // Update if messageId becomes available
          } : null);
        }

        showToast('Transaction recorded in history!', 'success');

        // Refresh data
        setTimeout(() => {
          fetchStrategyStats();
          fetchTokenBalance();
        }, 5000);
      }
      showToast(`Transaction sent! Hash: ${txHash}`, 'success');
    },
    onError: (err) => {
      console.error('Error in deposit operation:', err);
      showToast(`Error in deposit operation: ${err.message}`, 'error');
      // Close modal on operation error
      setShowSuccessModal(false);
      setSuccessData(null);
    },
  });

  // Show toast when error occurs
  useEffect(() => {
    if (error) {
      showToast(error, 'error');
    }
  }, [error, showToast]);

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
    <div className="treasure-page-container">

      <div className="treasure-header">
        <div className="treasure-title">
          <span>Deposit</span>
        </div>
      </div>

      <div className="treasure-card">
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px' }}>
          <div>
            <div className="treasure-stat-label">Total MAGIC Restaked</div>
            <div className="treasure-stat-value">
              <div className="magic-token-icon"></div>
              {isLoadingStrategyStats ? (
                <div className="loading-spinner"></div>
              ) : (
                <span>{formatNumber(totalStaked)}</span>
              )}
            </div>
          </div>
          <div>
            <div className="treasure-stat-label">MAGIC Price</div>
            <div className="treasure-stat-value">$0.143</div>
          </div>
        </div>
      </div>

      <div>
        <div className="treasure-card">
          <div className="treasure-stat-container" style={{ marginBottom: '20px' }}>
            <div className="treasure-stat-label">Balance</div>
            <div className="treasure-stat-value">
              <div className="magic-token-icon"></div>
              {isLoadingTokenBalance ? (
                <div className="loading-spinner"></div>
              ) : (
                <span>{tokenBalance ? formatNumber(tokenBalance) : '0.00'} MAGIC</span>
              )}
            </div>
          </div>

          <div style={{ marginBottom: '20px' }}>
            <div className="treasure-input-container">
              <input
                type="text"
                value={transactionAmount}
                onChange={handleAmountChange}
                placeholder="0.00"
                className="treasure-input"
                disabled={isInputDisabled}
              />
              <button
                className="treasure-max-button"
                onClick={handleMaxButtonClick}
                disabled={isInputDisabled || !tokenBalance || tokenBalance === 0n}
              >
                Max
              </button>
            </div>
          </div>

          <button
            className="treasure-action-button"
            style={{ width: '100%' }}
            disabled={isInputDisabled || (!eigenAgentInfo?.eigenAgentAddress && !predictedEigenAgentAddress)}
            onClick={handleDepositIntoStrategy}
          >
            {isExecuting ? (
              <>
                <span className="loading-spinner"></span>
                <span>{info === "Sending message to L1 Ethereum..." ? "Sending to L1..." : "Processing..."}</span>
              </>
            ) : isFirstTimeUser ? 'Mint EigenAgent & Deposit' : 'Deposit'}
          </button>

          <div className="first-time-notice">
            <strong>First-time User:</strong> This transaction will mint a new EigenAgent for you.
            <div className="predicted-address">Predicted address: {predictedEigenAgentAddress || 'Loading...'}</div>
          </div>

          {isApprovingToken && (
            <div style={{ marginTop: '16px', padding: '12px', backgroundColor: 'rgba(31, 111, 235, 0.1)', borderRadius: '8px', fontSize: '0.9rem' }}>
              <strong>Approving MAGIC tokens...</strong>
              {approvalHash && (
                <div style={{ marginTop: '8px' }}>
                  Approval Transaction:
                  <a
                    href={`${EXPLORER_URLS.basescan}/tx/${approvalHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    style={{ marginLeft: '6px', color: 'var(--treasure-accent-secondary)' }}
                  >
                    {approvalHash.substring(0, 10)}...
                  </a>
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Transaction Success Modal */}
      {successData && (
        <TransactionSuccessModal
          isOpen={showSuccessModal}
          onClose={handleCloseSuccessModal}
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

export default DepositPage;