import { useState } from 'react';
import { Address, Hex} from 'viem';
import { useClientsContext } from '../../contexts/ClientsContext';
import { signMessageForEigenAgentExecution } from '../../utils/signers';
import {
  EigenLayerOperationConfig,
  EigenAgentInfo
} from '../../types';
import { handleTokenApproval } from './tokenApproval';
import { dispatchTransaction } from './dispatchTransaction';
import {
  BaseSepolia,
  EthSepolia,
  STRATEGY_MANAGER_ADDRESS
} from '../../addresses';
import { APP_CONFIG } from '../../configs';

interface UseEigenLayerOperationResult {
  isExecuting: boolean;
  signature: Hex | null;
  error: string | null;
  info: string | null;
  isApprovingToken: boolean;
  approvalHash: string | null;
  executeWithMessage: (message: Hex) => Promise<void>;
}

/**
 * Hook for executing operations that require EigenAgent signatures and cross-chain messaging
 * This hook handles:
 * 1. Token approvals (if required)
 * 2. Chain switching for signing
 * 3. EigenAgent signature creation
 * 4. Transaction dispatch via CCIP
 */
export function useEigenLayerOperation({
  targetContractAddr,
  amount,
  tokenApproval,
  onSuccess,
  onError,
  expiryMinutes = APP_CONFIG.DEFAULT_EXPIRY_MINUTES,
  customGasLimit,
}: EigenLayerOperationConfig): UseEigenLayerOperationResult {
  const {
    l1Wallet,
    l2Wallet,
    switchChain,
    eigenAgentInfo,
    predictedEigenAgentAddress,
  } = useClientsContext();

  const [isExecuting, setIsExecuting] = useState(false);
  const [signature, setSignature] = useState<Hex | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [isApprovingToken, setIsApprovingToken] = useState(false);
  const [approvalHash, setApprovalHash] = useState<string | null>(null);

  /**
   * Signs a message for EigenAgent execution and handles chain switching
   */
  async function signMessage(
    wallet: any, // Using 'any' to avoid type conflicts
    agentAddress: Address,
    message: Hex,
    execNonce: bigint
  ): Promise<{ signature: Hex, messageWithSignature: Hex }> {
    if (!wallet.client || !wallet.account) {
      throw new Error("Wallet client not available");
    }

    const expiryTime = BigInt(Math.floor(Date.now() / 1000) + (expiryMinutes * 60));

    return signMessageForEigenAgentExecution(
      wallet.client,
      wallet.account,
      agentAddress,
      targetContractAddr,
      message,
      execNonce,
      expiryTime
    );
  }

  /**
   * Main function to execute a transaction with a message
   */
  const executeWithMessage = async (directMessage: Hex): Promise<void> => {
    setError(null);
    setSignature(null);
    setIsExecuting(true);
    let messageWithSignature: Hex | undefined = undefined;

    try {
      // Check if this is a deposit transaction (only type allowed for first-time users)
      const isDeposit = targetContractAddr === STRATEGY_MANAGER_ADDRESS;

      // For deposits, we can use either eigenAgentInfo,
      // or predictedEigenAgentAddress for first time users.
      // For other transaction types, we require eigenAgentInfo
      if ((!eigenAgentInfo && !predictedEigenAgentAddress && isDeposit) ||
          (!eigenAgentInfo && !isDeposit)) {
        setIsExecuting(false);
        if (isDeposit) {
          throw new Error("EigenAgent info not available. Please connect your wallet and ensure you have a registered agent.");
        } else {
          throw new Error("This operation requires an existing EigenAgent. Please deposit funds first to create your EigenAgent.");
        }
      }

      // Use the actual or predicted EigenAgent address only for deposits
      // For other transaction types, we must have eigenAgentInfo
      const agentAddress = eigenAgentInfo?.eigenAgentAddress ||
                          (isDeposit ? predictedEigenAgentAddress as Address : null);

      // If agentAddress is null, we can't proceed
      if (!agentAddress) {
        setIsExecuting(false);
        throw new Error("EigenAgent address not available. Please create an EigenAgent by depositing funds first.");
      }

      const execNonceValue = eigenAgentInfo?.execNonce || 0n; // Use 0 for first-time users

      // Handle token approval if needed
      if (tokenApproval) {
        try {
          setIsApprovingToken(true);
          setInfo("Checking token allowance...");

          const { hash, message } = await handleTokenApproval(
            l2Wallet as any, // Using 'any' to avoid type conflicts
            tokenApproval,
            agentAddress
          );

          if (hash) {
            setApprovalHash(hash);
          }

          setInfo(message);
          setInfo("Token allowance is sufficient");
        } catch (approvalError) {
          console.error('Error during token approval:', approvalError);
          setIsExecuting(false);
          setIsApprovingToken(false);

          const approvalErrorMsg = approvalError instanceof Error ? approvalError.message : String(approvalError);

          // Check if it's a user rejection
          if (approvalErrorMsg.toLowerCase().includes('rejected') ||
              approvalErrorMsg.toLowerCase().includes('denied') ||
              approvalErrorMsg.toLowerCase().includes('cancelled')) {
            setInfo("Token approval was cancelled");
          } else {
            setError(`Error approving token: ${approvalErrorMsg}`);
          }

          if (onError) onError(approvalError instanceof Error ? approvalError : new Error(String(approvalError)));
          return;
        } finally {
          setIsApprovingToken(false);
        }
      }

      // Switch to Ethereum Sepolia for signing
      setInfo("Temporarily switching to Ethereum Sepolia for signing...");
      await switchChain(l1Wallet.publicClient?.chain?.id ?? EthSepolia.chainId);

      // Wait a moment for the switch to take effect
      await new Promise(resolve => setTimeout(resolve, 1000));

      try {
        // Sign the message
        setInfo("Please sign the message with your wallet...");
        const result = await signMessage(
          l1Wallet,
          agentAddress,
          directMessage,
          execNonceValue
        );

        setSignature(result.signature);
        messageWithSignature = result.messageWithSignature;
        setInfo("Message signed successfully");
      } catch (signError) {
        // Handle signature rejection
        const errorMessage = signError instanceof Error ? signError.message : String(signError);
        console.log("Signature rejection detected:", errorMessage);

        // If the user rejected the signature request
        if (errorMessage.toLowerCase().includes('rejected') ||
            errorMessage.toLowerCase().includes('denied') ||
            errorMessage.toLowerCase().includes('user refused') ||
            errorMessage.toLowerCase().includes('cancelled') ||
            errorMessage.toLowerCase().includes('declined')) {

          // Important: Reset execution state FIRST
          setIsExecuting(false);

          // Show rejection as info, not error
          setInfo("Transaction signing was cancelled");

          // Make sure we switch back to Base Sepolia
          try {
            await switchChain(l2Wallet.publicClient?.chain?.id ?? BaseSepolia.chainId);
          } catch (switchBackError) {
            console.error('Error switching back to Base Sepolia:', switchBackError);
          }

          if (onError) onError(signError instanceof Error ? signError : new Error(String(signError)));
          return;
        }

        // For other signature errors, rethrow
        throw signError;
      }

      // Switch back to Base Sepolia
      setInfo("Switching back to Base Sepolia...");
      await switchChain(l2Wallet.publicClient?.chain?.id ?? BaseSepolia.chainId);

      // Wait for the switch to complete
      await new Promise(resolve => setTimeout(resolve, 1000));

      try {
        // Dispatch the transaction
        if (!messageWithSignature) {
          throw new Error("Failed to generate signature message");
        }

        setInfo("Please confirm the transaction in your wallet...");
        const { txHash, receipt } = await dispatchTransaction(
          l2Wallet as any, // Using 'any' to avoid type conflicts
          targetContractAddr,
          messageWithSignature,
          directMessage,
          amount,
          customGasLimit,
          setInfo
        );
        setInfo("Transaction submitted successfully");

        // Call onSuccess if provided
        if (onSuccess) {
          onSuccess(txHash, receipt);
        }

      } catch (txError) {
        // Handle transaction rejection or rate limit error
        const errorMessage = txError instanceof Error ? txError.message : String(txError);
        console.log("Transaction error detected:", errorMessage);

        // Check for rate limit error first
        if (errorMessage.includes('rate limit') || errorMessage.includes('429')) {
          setInfo("RPC rate limit exceeded. Your request will be retried automatically.");
          throw txError; // Let the retry logic handle it
        }

        // If the user rejected the transaction
        if (errorMessage.toLowerCase().includes('rejected') ||
            errorMessage.toLowerCase().includes('denied') ||
            errorMessage.toLowerCase().includes('user refused') ||
            errorMessage.toLowerCase().includes('cancelled') ||
            errorMessage.toLowerCase().includes('declined')) {

          // Important: Reset execution state FIRST
          setIsExecuting(false);

          // Show rejection as info, not error
          setInfo("Transaction was cancelled");

          if (onError) onError(txError instanceof Error ? txError : new Error(String(txError)));
          return;
        }

        // For other transaction errors, rethrow
        throw txError;
      }

    } catch (err) {
      // Make sure we always switch back to Base Sepolia if there's an error
      try {
        await switchChain(l2Wallet.publicClient?.chain?.id ?? BaseSepolia.chainId);
      } catch (switchBackError) {
        console.error('Error switching back to Base Sepolia:', switchBackError);
      }

      console.error('Error executing EigenLayer operation:', err);
      const errorMessage = err instanceof Error ? err.message : 'Failed to execute operation';
      console.log("General error handler detected:", errorMessage);

      // Check for rate limit errors
      if (typeof errorMessage === 'string' && errorMessage.includes('rate limit')) {
        setError(`RPC rate limit exceeded. Please try again in a few minutes.`);
        setInfo(`Your transaction may still be processing. Check your transaction history.`);
        if (onError) onError(err instanceof Error ? err : new Error(String(err)));
        return;
      }

      // Check if this error is a user rejection that wasn't caught by the specific handlers
      if (typeof errorMessage === 'string' &&
         (errorMessage.toLowerCase().includes('rejected') ||
          errorMessage.toLowerCase().includes('denied') ||
          errorMessage.toLowerCase().includes('user refused') ||
          errorMessage.toLowerCase().includes('cancelled') ||
          errorMessage.toLowerCase().includes('declined'))) {

        // Important: Reset execution state FIRST
        setIsExecuting(false);

        // Show rejection as info, not error
        setInfo(`Operation was rejected: ${errorMessage}`);

        if (onError) onError(err instanceof Error ? err : new Error(String(err)));
        return;
      }

      // For non-rejection errors, set the error message
      setError(`Error: ${errorMessage}`);

      if (onError) onError(err instanceof Error ? err : new Error(String(err)));
    } finally {
      // Ensure isExecuting is always reset when the function completes
      setIsExecuting(false);
    }
  };

  return {
    isExecuting,
    signature,
    error,
    info,
    isApprovingToken,
    approvalHash,
    executeWithMessage
  };
}

// Export other modules
export * from './utils';
export * from './tokenApproval';
export * from './dispatchTransaction';