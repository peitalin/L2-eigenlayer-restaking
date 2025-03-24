import React, { useState, useEffect } from 'react';
import { Address, Hex, getAddress, toHex, bytesToHex } from 'viem';
import { useClientsContext } from '../contexts/ClientsContext';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { useEigenLayerOperation } from '../hooks/useEigenLayerOperation';
import { encodeUndelegateMsg, encodeDelegateTo, SignatureWithExpiry } from '../utils/encoders';
import { calculateDelegationApprovalDigestHash, signDelegationApproval } from '../utils/signers';
import { DELEGATION_MANAGER_ADDRESS, EthSepolia, BaseSepolia } from '../addresses';
import Expandable from '../components/Expandable';
import TransactionSuccessModal from '../components/TransactionSuccessModal';
import { TransactionType } from '../types';

// Hardcoded operator address for sample demonstration
// This should be replaced with a list of valid operators from a database or contract
const SAMPLE_OPERATORS = [
  '0x0000000000000000000000000000000000000004', // address(4) converted
  '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045', // vitalik.eth
  '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B', // Another example address
];

const DelegatePage: React.FC = () => {
  const { l1Wallet, l2Wallet, eigenAgentInfo, predictedEigenAgentAddress } = useClientsContext();
  const { addTransaction } = useTransactionHistory();

  const [selectedOperator, setSelectedOperator] = useState<Address | null>(SAMPLE_OPERATORS[0] as Address);
  const [isCurrentlyDelegated, setIsCurrentlyDelegated] = useState(false);
  const [currentOperator, setCurrentOperator] = useState<Address | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Add state for success modal
  const [showSuccessModal, setShowSuccessModal] = useState(false);
  const [successData, setSuccessData] = useState<{
    txHash: string;
    messageId: string;
    operationType: 'delegate' | 'undelegate';
    isLoading: boolean;
  } | null>(null);

  // Use useEigenLayerOperation for delegation
  const delegateOperation = useEigenLayerOperation({
    targetContractAddr: DELEGATION_MANAGER_ADDRESS,
    amount: 0n, // No tokens sent for delegation
    customGasLimit: 400000n, // Fixed gas limit for delegateTo as specified
    onSuccess: (txHash, receipt) => {
      setIsCurrentlyDelegated(true);
      setCurrentOperator(selectedOperator);

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
        receiptTransactionHash: receipt.transactionHash
      };

      // Add transaction to history
      addTransaction(txData);

      // Update the existing success modal with transaction data
      if (successData) {
        setSuccessData({
          ...successData,
          txHash,
          messageId: txData.messageId || "",
          isLoading: false
        });
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
    customGasLimit: 300000n, // Less gas required for undelegation
    onSuccess: (txHash, receipt) => {
      setIsCurrentlyDelegated(false);
      setCurrentOperator(null);

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
        receiptTransactionHash: receipt.transactionHash
      };

      // Add transaction to history
      addTransaction(txData);

      // Update the existing success modal with transaction data
      if (successData) {
        setSuccessData({
          ...successData,
          txHash,
          messageId: txData.messageId || "",
          isLoading: false
        });
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
        setCurrentOperator(isZeroAddress ? null : operatorAddress);
      } catch (err) {
        console.error('Error checking delegation status:', err);
        setError('Could not check delegation status');
      } finally {
        setIsLoading(false);
      }
    };

    checkDelegationStatus();
  }, [l1Wallet.publicClient, eigenAgentInfo?.eigenAgentAddress]);

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
      setSuccessData({
        txHash: '',
        messageId: '',
        operationType: 'delegate',
        isLoading: true
      });
      setShowSuccessModal(true);

      // Create a random salt as bytes32
      const randomSalt = bytesToHex(window.crypto.getRandomValues(new Uint8Array(32)));

      // Set expiry to 1 hour from now (similar to the Solidity script)
      const expiry = BigInt(Math.floor(Date.now() / 1000) + 3600);

      // The eigenAgent address is the staker from Eigenlayer's perspective
      const eigenAgentAddress = eigenAgentInfo?.eigenAgentAddress || predictedEigenAgentAddress as Address;

      // For the demo, we'll use the operator as both operator and delegationApprover
      // In a real scenario, the delegationApprover would be a separate entity that signs to approve delegation
      const delegationApprover = selectedOperator;

      // Calculate the digest hash that needs to be signed
      const digestHash = calculateDelegationApprovalDigestHash(
        eigenAgentAddress,
        selectedOperator,
        delegationApprover,
        randomSalt,
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
        selectedOperator,
        delegationApprover,
        randomSalt,
        expiry
      );

      // Create the SignatureWithExpiry struct
      const approverSignatureAndExpiry: SignatureWithExpiry = {
        signature,
        expiry
      };

      // Encode the delegateTo message
      const delegateToMessage = encodeDelegateTo(
        selectedOperator,
        approverSignatureAndExpiry,
        randomSalt
      );

      // Execute the delegation operation
      await delegateOperation.executeWithMessage(delegateToMessage);

    } catch (err) {
      console.error('Error during delegation:', err);
      setError(`Delegation error: ${err instanceof Error ? err.message : String(err)}`);
      setShowSuccessModal(false);
      setSuccessData(null);
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

    try {
      setIsLoading(true);

      // Show the modal with loading state first
      setSuccessData({
        txHash: '',
        messageId: '',
        operationType: 'undelegate',
        isLoading: true
      });
      setShowSuccessModal(true);

      // Encode the undelegate message
      const undelegateMessage = encodeUndelegateMsg(eigenAgentInfo.eigenAgentAddress);

      // Execute the undelegation operation
      await undelegateOperation.executeWithMessage(undelegateMessage);

    } catch (err) {
      console.error('Error during undelegation:', err);
      setError(`Undelegation error: ${err instanceof Error ? err.message : String(err)}`);
      setShowSuccessModal(false);
      setSuccessData(null);
    } finally {
      setIsLoading(false);
    }
  };

  const handleCloseSuccessModal = () => {
    // Only allow closing if not loading or if we have an error
    if (!successData?.isLoading || error) {
      setShowSuccessModal(false);
      setSuccessData(null);
    }
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
            <p>You are currently delegated to: <span className="font-mono">{currentOperator}</span></p>
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
              <label htmlFor="operator">Select an operator to delegate to:</label>
              <select
                id="operator"
                className="amount-input operator-select"
                value={selectedOperator || ''}
                onChange={(e) => setSelectedOperator(e.target.value as Address)}
                disabled={isCurrentlyDelegated || isLoading}
              >
                <option value="">-- Select an operator --</option>
                {SAMPLE_OPERATORS.map((op) => (
                  <option
                    key={op}
                    value={op}
                  >
                    {op}
                  </option>
                ))}
              </select>
            </div>

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

            <Expandable title="Delegation Information" initialExpanded={false}>
              <h3>Notes:</h3>
              <ul>
                <li>Delegation requires the operator's approval via signature</li>
                <li>This demo uses simplified logic; in production, the operator would need to provide their signature</li>
                <li>Once delegated, you must undelegate before delegating to a different operator</li>
                <li>Undelegation initiates a withdrawal queue for your funds with a 7-day waiting period</li>
              </ul>
            </Expandable>

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