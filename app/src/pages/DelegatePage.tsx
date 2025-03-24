import React, { useState, useEffect, useRef } from 'react';
import { Address, Hex, getAddress, toHex, bytesToHex } from 'viem';
import { useClientsContext } from '../contexts/ClientsContext';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { encodeUndelegateMsg, encodeDelegateTo, SignatureWithExpiry } from '../utils/encoders';
import { signDelegationApprovalServer } from '../utils/signers';
import { DELEGATION_MANAGER_ADDRESS, EthSepolia, BaseSepolia } from '../addresses';
import TransactionSuccessModal from '../components/TransactionSuccessModal';
import { TransactionType } from '../types';
import { SERVER_BASE_URL } from '../configs';
import { useToast } from '../utils/toast';

// Define the Operator type
interface Operator {
  name: string;
  address: string;
  magicStaked: string;
  ethStaked: string;
  stakers: number;
  fee: string;
  isActive: boolean;
}

const DelegatePage: React.FC = () => {
  const { l1Wallet, l2Wallet, eigenAgentInfo, predictedEigenAgentAddress } = useClientsContext();
  const { addTransaction } = useTransactionHistory();
  const { showToast } = useToast();
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [selectedOperator, setSelectedOperator] = useState<string>('');
  const [isCurrentlyDelegated, setIsCurrentlyDelegated] = useState<boolean>(false);
  const [currentDelegation, setCurrentDelegation] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [operators, setOperators] = useState<Operator[]>([]);
  const [isLoadingOperators, setIsLoadingOperators] = useState<boolean>(false);

  // Add state for success modal
  const [showSuccessModal, setShowSuccessModal] = useState(false);
  const [successData, setSuccessData] = useState<{
    txHash: string;
    messageId: string;
    operationType: 'delegate' | 'undelegate';
    isLoading: boolean;
  } | null>(null);

  // Use a ref to track if the modal is currently showing
  const modalVisibleRef = useRef(false);

  // Update the ref when the modal visibility changes
  useEffect(() => {
    modalVisibleRef.current = showSuccessModal;
  }, [showSuccessModal]);

  // Fetch operators from the server
  useEffect(() => {
    const fetchOperators = async () => {
      setIsLoadingOperators(true);
      try {
        const response = await fetch(`${SERVER_BASE_URL}/api/operators?showInactive=true`);
        if (!response.ok) {
          throw new Error('Failed to fetch operators');
        }
        const data = await response.json();
        setOperators(data);
      } catch (err) {
        console.error('Error fetching operators:', err);
        setError('Failed to load operators');
      } finally {
        setIsLoadingOperators(false);
      }
    };

    fetchOperators();
  }, []);

  // Use useEigenLayerOperation for delegation
  const delegateOperation = useEigenLayerOperation({
    targetContractAddr: DELEGATION_MANAGER_ADDRESS,
    amount: 0n, // No tokens sent for delegation
    customGasLimit: 400000n, // Fixed gas limit for delegateTo as specified
    onSuccess: (txHash, receipt, execNonce) => {
      setIsCurrentlyDelegated(true);
      setCurrentDelegation(selectedOperator);

      // Prepare transaction data for history
      const txData = {
        txHash,
        messageId: "", // Server will extract the real messageId if needed
        timestamp: Math.floor(Date.now() / 1000),
        txType: 'delegateTo' as TransactionType,
        status: 'confirmed' as 'pending' | 'confirmed' | 'failed',
        from: receipt.from,
        to: receipt.to || '',
        user: l1Wallet.account || '',
        isComplete: false,
        sourceChainId: BaseSepolia.chainId.toString(),
        destinationChainId: EthSepolia.chainId.toString(),
        receiptTransactionHash: receipt.transactionHash,
        execNonce: execNonce
      };

      // Add transaction to history
      addTransaction(txData);

      // Force create a new modal state object to ensure React notices the change
      const updatedData = {
        txHash: txHash,
        messageId: txData.messageId || "",
        operationType: 'delegate' as const,
        isLoading: false
      };

      // Only update if modal is still visible (to prevent state updates after component unmounted)
      if (modalVisibleRef.current) {
        // Completely replace the state (don't use the previous state)
        setSuccessData(updatedData);

        // Auto-close the modal after 5 seconds
        setTimeout(() => {
          if (modalVisibleRef.current) {
            setShowSuccessModal(false);
            setSuccessData(null);
          }
        }, 5000);
      }
    },
    onError: (err) => {
      // Close the modal if there's an error
      setShowSuccessModal(false);
      setSuccessData(null);

      // Check if it's a user rejection
      const errorMessage = err.message.toLowerCase();
      if (errorMessage.includes('rejected') ||
          errorMessage.includes('denied') ||
          errorMessage.includes('cancelled') ||
          errorMessage.includes('user refused') ||
          errorMessage.includes('declined')) {
        showToast('Transaction was cancelled', 'info');
      } else {
        setError(`Delegation failed: ${err.message}`);
      }
    }
  });

  // Use useEigenLayerOperation for undelegation
  const undelegateOperation = useEigenLayerOperation({
    targetContractAddr: DELEGATION_MANAGER_ADDRESS,
    amount: 0n, // No tokens sent for undelegation
    customGasLimit: 650000n,
    onSuccess: (txHash, receipt, execNonce) => {
      setIsCurrentlyDelegated(false);
      setCurrentDelegation(null);

      // Prepare transaction data for history
      const txData = {
        txHash,
        messageId: "", // Server will extract the real messageId if needed
        timestamp: Math.floor(Date.now() / 1000),
        txType: 'undelegate' as TransactionType,
        status: 'confirmed' as 'pending' | 'confirmed' | 'failed',
        from: receipt.from,
        to: receipt.to || '',
        user: l2Wallet.account || '',
        isComplete: false,
        sourceChainId: BaseSepolia.chainId.toString(),
        destinationChainId: EthSepolia.chainId.toString(),
        receiptTransactionHash: receipt.transactionHash,
        execNonce: execNonce
      };

      // Add transaction to history
      addTransaction(txData);

      // Force create a new modal state object to ensure React notices the change
      const updatedData = {
        txHash: txHash,
        messageId: txData.messageId || "",
        operationType: 'undelegate' as const,
        isLoading: false
      };

      // Only update if modal is still visible (to prevent state updates after component unmounted)
      if (modalVisibleRef.current) {
        // Completely replace the state (don't use the previous state)
        setSuccessData(updatedData);

        // Auto-close the modal after 5 seconds
        setTimeout(() => {
          if (modalVisibleRef.current) {
            setShowSuccessModal(false);
            setSuccessData(null);
          }
        }, 5000);
      }
    },
    onError: (err) => {
      // Close the modal if there's an error
      setShowSuccessModal(false);
      setSuccessData(null);

      // Check if it's a user rejection
      const errorMessage = err.message.toLowerCase();
      if (errorMessage.includes('rejected') ||
          errorMessage.includes('denied') ||
          errorMessage.includes('cancelled') ||
          errorMessage.includes('user refused') ||
          errorMessage.includes('declined')) {
        showToast('Transaction was cancelled', 'info');
      } else {
        setError(`Undelegation failed: ${err.message}`);
      }
    }
  });

  // Check if the user is already delegated
  useEffect(() => {
    const checkDelegationStatus = async () => {
      if (!l1Wallet.publicClient || !eigenAgentInfo?.eigenAgentAddress) {
        setIsLoading(false);
        return;
      }

      try {
        // Call the IDelegationManager.delegatedTo function to check current delegation
        const result = await l1Wallet.publicClient.readContract({
          address: DELEGATION_MANAGER_ADDRESS,
          abi: [{
            name: 'delegatedTo',
            type: 'function',
            inputs: [{ name: 'staker', type: 'address' }],
            outputs: [{ name: '', type: 'address' }],
            stateMutability: 'view'
          }],
          functionName: 'delegatedTo',
          args: [eigenAgentInfo.eigenAgentAddress]
        });

        // If returned address is not zero, user is delegated
        const operatorAddress = result as Address;
        const isZeroAddress = operatorAddress === '0x0000000000000000000000000000000000000000';

        setIsCurrentlyDelegated(!isZeroAddress);
        setCurrentDelegation(isZeroAddress ? null : operatorAddress.toString());
      } catch (err) {
        console.error('Error checking delegation status:', err);
        setError('Could not check delegation status');
      } finally {
        setIsLoading(false);
      }
    };

    checkDelegationStatus();
  }, [l1Wallet.publicClient, eigenAgentInfo?.eigenAgentAddress]);

  // Find the currently selected operator details
  const selectedOperatorDetails = operators.find(op => op.address === selectedOperator);

  // Render the operator selection table
  const renderOperatorTable = () => {
    if (isLoadingOperators) {
      return (
        <div className="treasure-empty-state">
          <div className="loading-spinner"></div>
          <p className="treasure-empty-text">Loading operators...</p>
        </div>
      );
    }

    return (
      <div className="treasure-table-container">
        <table className="treasure-table">
          <thead>
            <tr className="treasure-table-header">
              <th></th>
              <th>Operator Name</th>
              <th>Operator Address</th>
              <th>MAGIC Staked</th>
              <th>ETH Staked</th>
              <th>No. Stakers</th>
              <th>Operator Fee</th>
            </tr>
          </thead>
          <tbody>
            {operators.map((operator) => (
              <tr
                key={operator.address}
                className={`treasure-table-row ${selectedOperator === operator.address ? 'selected-operator' : ''} ${!operator.isActive ? 'inactive-operator' : ''}`}
                onClick={() => {
                  if (!isCurrentlyDelegated && !isLoading && operator.isActive) {
                    setSelectedOperator(operator.address);
                  }
                }}
              >
                <td className="treasure-table-cell">
                  <input
                    type="radio"
                    name="operator"
                    checked={selectedOperator === operator.address}
                    onChange={() => {
                      if (operator.isActive) {
                        setSelectedOperator(operator.address);
                      }
                    }}
                    disabled={isCurrentlyDelegated || isLoading || !operator.isActive}
                  />
                </td>
                <td className="treasure-table-cell">{operator.name}</td>
                <td className="treasure-table-cell font-mono">{operator.address.substring(0, 6)}...{operator.address.substring(operator.address.length - 4)}</td>
                <td className="treasure-table-cell">{operator.magicStaked}</td>
                <td className="treasure-table-cell">{operator.ethStaked}</td>
                <td className="treasure-table-cell">{operator.stakers}</td>
                <td className="treasure-table-cell">{operator.fee}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  };

  // Handle delegation to selected operator
  const handleDelegate = async () => {
    if (!selectedOperator) {
      setError('Please select an operator to delegate to');
      return;
    }

    if (!l1Wallet.client || !l1Wallet.account) {
      setError('Wallet not connected');
      return;
    }

    if (!eigenAgentInfo?.eigenAgentAddress && !predictedEigenAgentAddress) {
      setError('EigenAgent not found. Please deposit funds first to create an EigenAgent.');
      return;
    }

    try {
      setIsLoading(true);

      // Show the modal with loading state first
      const initialModalData = {
        txHash: '',
        messageId: '',
        operationType: 'delegate' as const,
        isLoading: true
      };
      setSuccessData(initialModalData);
      setShowSuccessModal(true);

      // Create a random salt as bytes32
      const randomSalt = bytesToHex(window.crypto.getRandomValues(new Uint8Array(32)));

      // The eigenAgent address is the staker from Eigenlayer's perspective
      const eigenAgentAddress = eigenAgentInfo?.eigenAgentAddress || predictedEigenAgentAddress as Address;

      // For the demo, we'll use the operator as both operator and delegationApprover
      // In a real scenario, the delegationApprover would be a separate entity that signs to approve delegation

      // Get the signature from the connected wallet
      // NOTE: In a real implementation, the operator should provide this signature
      // For demo purposes, we're signing on behalf of the operator which isn't valid in practice
      const { signature, expiry } = await signDelegationApprovalServer(
        eigenAgentAddress,
        getAddress(selectedOperator),
      );

      if (!signature || !expiry) {
        setError('Failed to sign delegation approval');
        return;
      }

      // Create the SignatureWithExpiry struct
      const approverSignatureAndExpiry: SignatureWithExpiry = {
        signature: signature as `0x${string}`,
        expiry: BigInt(expiry)
      };

      // Encode the delegateTo message
      const delegateToMessage = encodeDelegateTo(
        getAddress(selectedOperator),
        approverSignatureAndExpiry,
        randomSalt as `0x${string}`
      );

      // Execute the delegation operation
      const result = await delegateOperation.executeWithMessage(delegateToMessage);

      // Add the transaction with the execNonce
      if (result && result.execNonce !== undefined) {
      }

    } catch (err) {
      console.error('Error during delegation:', err);
      setError(`Delegation error: ${err instanceof Error ? err.message : String(err)}`);

      // Only update modal state if it's still visible
      if (modalVisibleRef.current) {
        setShowSuccessModal(false);
        setSuccessData(null);
      }
    } finally {
      setIsLoading(false);
    }
  };

  // Handle undelegation
  const handleUndelegate = async () => {
    if (!isCurrentlyDelegated) {
      setError('You are not currently delegated');
      return;
    }

    if (!eigenAgentInfo?.eigenAgentAddress) {
      setError('EigenAgent not found');
      return;
    }

    const eigenAgentAddress = eigenAgentInfo.eigenAgentAddress;

    try {
      setIsLoading(true);

      // Show the modal with loading state first
      const initialModalData = {
        txHash: '',
        messageId: '',
        operationType: 'undelegate' as const,
        isLoading: true
      };
      setSuccessData(initialModalData);
      setShowSuccessModal(true);

      // Encode the undelegate message
      const undelegateMessage = encodeUndelegateMsg(eigenAgentAddress);

      // Execute the undelegation operation
      const result = await undelegateOperation.executeWithMessage(undelegateMessage);

    } catch (err) {
      console.error('Error during undelegation:', err);
      setError(`Undelegation error: ${err instanceof Error ? err.message : String(err)}`);

      // Only update modal state if it's still visible
      if (modalVisibleRef.current) {
        setShowSuccessModal(false);
        setSuccessData(null);
      }
    } finally {
      setIsLoading(false);
    }
  };

  const handleCloseSuccessModal = () => {
    // Remove the condition - allow closing the modal anytime the button is clicked
    setShowSuccessModal(false);
    setSuccessData(null);
  };

  return (
    <div className="treasure-page-container">
      <div className="treasure-header">
        <div className="treasure-title">
          <span>Delegate</span>
        </div>
      </div>

      <div className="treasure-card">
        <div className="treasure-card-header">
          <div className="treasure-card-title">Current Operator</div>
        </div>
        {isLoading ? (
          <div className="treasure-empty-state">
            <div className="loading-spinner"></div>
            <p className="treasure-empty-text">Loading delegation status...</p>
          </div>
        ) : isCurrentlyDelegated ? (
          <div>
            <div className="treasure-info-item">
              <span className="treasure-info-label">Currently delegated to:</span>
              <span className="treasure-info-value font-mono">{currentDelegation}</span>
            </div>
            <button
              onClick={handleUndelegate}
              disabled={undelegateOperation.isExecuting || isLoading}
              className="treasure-action-button"
              style={{ marginTop: '16px', width: '100%' }}
            >
              {undelegateOperation.isExecuting ? 'Processing...' : 'Undelegate'}
            </button>
          </div>
        ) : (
          <div className="treasure-empty-state">
            <p className="treasure-empty-text">You are not currently delegated to any operator.</p>
            </div>
        )}
      </div>

      <div className="treasure-card">
        <div className="treasure-card-header">
          <div className="treasure-card-title">Delegate to Operator</div>
        </div>
        {!eigenAgentInfo?.eigenAgentAddress && !predictedEigenAgentAddress ? (
          <div className="treasure-empty-state">
            <p className="treasure-empty-text">You need to deposit funds first to create an EigenAgent.</p>
            <button
              onClick={() => window.location.href = '/deposit'}
              className="treasure-action-button"
              style={{ marginTop: '16px' }}
              disabled={isLoading}
            >
              Go to Deposit
            </button>
          </div>
        ) : (
          <>
            <div>
              {renderOperatorTable()}
            </div>

            {selectedOperator && selectedOperatorDetails && (
              <div className="treasure-info-section" style={{ marginTop: '24px' }}>
                <div className="treasure-info-item">
                  <span className="treasure-info-label">Selected Operator:</span>
                  <span className="treasure-info-value">{selectedOperatorDetails.name}</span>
                </div>
                <div className="treasure-info-item">
                  <span className="treasure-info-label">Fee:</span>
                  <span className="treasure-info-value">{selectedOperatorDetails.fee}</span>
                </div>
              </div>
            )}

            <button
              onClick={handleDelegate}
              disabled={!selectedOperator || isCurrentlyDelegated || delegateOperation.isExecuting || isLoading}
              className="treasure-action-button"
              style={{ width: '100%', marginTop: '16px' }}
            >
              {isLoading ? (
                <>
                  <span className="loading-spinner"></span>
                  <span>Loading...</span>
                </>
              ) : delegateOperation.isExecuting ? (
                <>
                  <span className="loading-spinner"></span>
                  <span>Processing...</span>
                </>
              ) : (
                'Delegate'
              )}
            </button>

            {error && (
              <div className="treasure-info-section error" style={{ marginTop: '20px' }}>
                <div className="treasure-info-item">
                  <span className="treasure-info-value error-text">{error}</span>
                  <button onClick={() => setError(null)} className="treasure-secondary-button" style={{ padding: '4px 8px', marginLeft: '8px' }}>×</button>
                </div>
              </div>
            )}
          </>
        )}
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
        />
      )}
    </div>
  );
};

export default DelegatePage;