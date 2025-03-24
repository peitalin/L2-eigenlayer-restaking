import React, { useState, useEffect, useRef } from 'react';
import { Address, Hex, getAddress, toHex, bytesToHex } from 'viem';
import { useClientsContext } from '../contexts/ClientsContext';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { encodeUndelegateMsg, encodeDelegateTo, SignatureWithExpiry } from '../utils/encoders';
import { calculateDelegationApprovalDigestHash, signDelegationApproval } from '../utils/signers';
import { DELEGATION_MANAGER_ADDRESS, EthSepolia, BaseSepolia } from '../addresses';
import TransactionSuccessModal from '../components/TransactionSuccessModal';
import { TransactionType } from '../types';
import { SERVER_BASE_URL } from '../configs';

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
      setError(`Delegation failed: ${err.message}`);
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
      setError(`Undelegation failed: ${err.message}`);
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
        <div className="loading-container">
          <div className="loading-spinner"></div>
          <p>Loading operators...</p>
        </div>
      );
    }

    return (
      <div className="operator-table-container">
        <table className="operator-table">
          <thead>
            <tr>
              <th></th>
              <th>Operator Name</th>
              <th>Operator Address</th>
              <th>Total MAGIC Staked</th>
              <th>Total ETH Staked</th>
              <th>No. Stakers</th>
              <th>Operator Fee</th>
            </tr>
          </thead>
          <tbody>
            {operators.map((operator) => (
              <tr
                key={operator.address}
                className={`${selectedOperator === operator.address ? 'selected-operator' : ''} ${!operator.isActive ? 'inactive-operator' : ''}`}
                onClick={() => {
                  if (!isCurrentlyDelegated && !isLoading && operator.isActive) {
                    setSelectedOperator(operator.address);
                  }
                }}
              >
                <td>
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
                <td>{operator.name}</td>
                <td className="font-mono address-cell">{operator.address.substring(0, 6)}...{operator.address.substring(operator.address.length - 4)}</td>
                <td>{operator.magicStaked}</td>
                <td>{operator.ethStaked}</td>
                <td>{operator.stakers}</td>
                <td>{operator.fee}</td>
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

      // Set expiry to 1 hour from now (similar to the Solidity script)
      const expiry = BigInt(Math.floor(Date.now() / 1000) + 3600);

      // The eigenAgent address is the staker from Eigenlayer's perspective
      const eigenAgentAddress = eigenAgentInfo?.eigenAgentAddress || predictedEigenAgentAddress as Address;

      // For the demo, we'll use the operator as both operator and delegationApprover
      // In a real scenario, the delegationApprover would be a separate entity that signs to approve delegation
      const delegationApprover = getAddress(selectedOperator);

      // Calculate the digest hash that needs to be signed
      const digestHash = calculateDelegationApprovalDigestHash(
        eigenAgentAddress,
        getAddress(selectedOperator),
        delegationApprover,
        randomSalt as `0x${string}`,
        expiry,
        DELEGATION_MANAGER_ADDRESS,
        EthSepolia.chainId
      );

      // Get the signature from the connected wallet
      // NOTE: In a real implementation, the operator should provide this signature
      // For demo purposes, we're signing on behalf of the operator which isn't valid in practice
      const signature = await signDelegationApproval(
        l1Wallet.client,
        l1Wallet.account,
        eigenAgentAddress,
        getAddress(selectedOperator),
        delegationApprover,
        randomSalt as `0x${string}`,
        expiry
      );

      // Create the SignatureWithExpiry struct
      const approverSignatureAndExpiry: SignatureWithExpiry = {
        signature,
        expiry
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
        // The execNonce was used for this transaction, store it
        const txData = {
          txHash: result.txHash,
          messageId: "",
          timestamp: Math.floor(Date.now() / 1000),
          txType: 'delegateTo' as TransactionType,
          status: 'confirmed' as 'pending' | 'confirmed' | 'failed',
          from: result.receipt.from,
          to: result.receipt.to || '',
          user: eigenAgentAddress,
          execNonce: result.execNonce,
          isComplete: false,
          sourceChainId: BaseSepolia.chainId.toString(),
          destinationChainId: EthSepolia.chainId.toString(),
          receiptTransactionHash: result.receipt.transactionHash
        };

        // Add transaction to history
        await addTransaction(txData);
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

      // Add the transaction with the execNonce
      if (result && result.execNonce !== undefined) {
        // The execNonce was used for this transaction, store it
        const txData = {
          txHash: result.txHash,
          messageId: "",
          timestamp: Math.floor(Date.now() / 1000),
          txType: 'undelegate' as TransactionType,
          status: 'confirmed' as 'pending' | 'confirmed' | 'failed',
          from: result.receipt.from,
          to: result.receipt.to || '',
          user: eigenAgentAddress,
          execNonce: result.execNonce,
          isComplete: false,
          sourceChainId: BaseSepolia.chainId.toString(),
          destinationChainId: EthSepolia.chainId.toString(),
          receiptTransactionHash: result.receipt.transactionHash
        };

        // Add transaction to history
        await addTransaction(txData);
      }

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
    <div className="deposit-page">
      <div className="transaction-form">
        <h2>Current Delegation Status</h2>
        {isLoading ? (
          <div className="info-banner">
            <div className="loading-spinner"></div>
            <p>Loading delegation status...</p>
          </div>
        ) : isCurrentlyDelegated ? (
          <div className="info-banner success">
            <p>You are currently delegated to: <span className="font-mono">{currentDelegation}</span></p>
            <button
              onClick={handleUndelegate}
              disabled={undelegateOperation.isExecuting || isLoading}
              className="create-transaction-button danger max-width-input"
            >
              {undelegateOperation.isExecuting ? 'Processing...' : 'Undelegate'}
            </button>
          </div>
        ) : (
          <div className="info-banner">
            You are not currently delegated to any operator.
          </div>
        )}
      </div>

      <div className="transaction-form">
        <h2>Delegate to Operator</h2>
        {!eigenAgentInfo?.eigenAgentAddress && !predictedEigenAgentAddress ? (
          <div className="info-banner warning">
            <p>You need to deposit funds first to create an EigenAgent.</p>
            <button
              onClick={() => window.location.href = '/deposit'}
              className="create-transaction-button max-width-input"
              disabled={isLoading}
            >
              Go to Deposit
            </button>
          </div>
        ) : (
          <>
            <div className="form-group">
              <h3>Select an operator to delegate to:</h3>
              {renderOperatorTable()}
            </div>

            {selectedOperator && (
              <div className="selected-operator-info">
                <p>Selected Operator: <strong>{selectedOperatorDetails?.name}</strong></p>
                <p>Fee: <strong>{selectedOperatorDetails?.fee}</strong></p>
              </div>
            )}

            <button
              onClick={handleDelegate}
              disabled={!selectedOperator || isCurrentlyDelegated || delegateOperation.isExecuting || isLoading}
              className="create-transaction-button max-width-input"
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
              <div className="info-banner error" style={{ marginTop: '20px', maxWidth: '100%', overflow: 'hidden', wordBreak: 'break-word' }}>
                {error}
                <button onClick={() => setError(null)} className="close-button">×</button>
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