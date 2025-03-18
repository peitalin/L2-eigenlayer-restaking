import { useState, useEffect } from 'react';
import { Address, Hex, formatEther, encodeAbiParameters } from 'viem';
import { baseSepolia } from '../hooks/useClients';
import { useClientsContext } from '../contexts/ClientsContext';
import { signMessageForEigenAgentExecution } from '../utils/signers';
import { CHAINLINK_CONSTANTS, SENDER_CCIP_ADDRESS, STRATEGY_MANAGER_ADDRESS } from '../addresses';
import { getRouterFeesL2 } from '../utils/routerFees';
import { RECEIVER_CCIP_ADDRESS } from '../addresses/ethSepoliaContracts';
import { IERC20ABI } from '../abis';
import { useTransactionHistory } from '../contexts/TransactionHistoryContext';
import { watchCCIPTransaction } from '../utils/ccipEventListener';
import { useToast } from '../utils/toast';

// Define function selector constants for better maintainability
// These are the first 4 bytes of the keccak256 hash of the function signature
const QUEUE_WITHDRAWAL_SELECTOR = '0x0dd8dd02' as Hex; // queueWithdrawals((address[],uint256[],address)[])
const COMPLETE_WITHDRAWAL_SELECTOR = '0xe4cc3f90' as Hex; // completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],bool)
const SEND_MESSAGE_PAY_NATIVE_SELECTOR = '0x7132732a' as Hex; // sendMessagePayNative(uint64,address,bytes,tuple[],uint256)

type TokenApproval = {
  tokenAddress: Address;
  spenderAddress: Address;
  amount: bigint;
}

interface EigenLayerOperationConfig {
  // Target for the EigenAgent to call on L1
  targetContractAddr: Address;
  // Amount of tokens to send with the operation
  amount: bigint;
  // Optional token approval details
  tokenApproval?: TokenApproval;
  // Function to call after successful operation
  onSuccess?: (txHash: string) => void;
  // Function to call after failure
  onError?: (error: Error) => void;
  // Minutes until the signature expires
  expiryMinutes?: number;
}

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
  expiryMinutes = 60,
}: EigenLayerOperationConfig): UseEigenLayerOperationResult {
  const {
    l1Wallet,
    l2Wallet,
    switchChain,
    eigenAgentInfo,
  } = useClientsContext();

  // Get transaction history context
  const { addTransaction } = useTransactionHistory();

  // Access toast functionality
  const { showToast } = useToast();

  const [isExecuting, setIsExecuting] = useState(false);
  const [signature, setSignature] = useState<Hex | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [isApprovingToken, setIsApprovingToken] = useState(false);
  const [approvalHash, setApprovalHash] = useState<string | null>(null);

  // Function to check token allowance
  const checkTokenAllowance = async (tokenAddress: Address, ownerAddress: Address, spenderAddress: Address): Promise<bigint> => {
    try {
      if (!l2Wallet.publicClient) {
        throw new Error("Public client not available for Base Sepolia");
      }

      const allowance = await l2Wallet.publicClient.readContract({
        address: tokenAddress,
        abi: IERC20ABI,
        functionName: 'allowance',
        args: [ownerAddress, spenderAddress]
      });

      return allowance as bigint;
    } catch (error) {
      console.error('Error checking token allowance:', error);
      throw error;
    }
  };

  // Function to approve token spending
  const approveTokenSpending = async (tokenAddress: Address, spenderAddress: Address, amount: bigint): Promise<string> => {
    try {
      setIsApprovingToken(true);

      if (!l2Wallet.client || !l2Wallet.account) {
        throw new Error("Wallet client not available for Base Sepolia");
      }

      // Check current allowance first
      const currentAllowance = await checkTokenAllowance(tokenAddress, l2Wallet.account, spenderAddress);

      // If allowance is already sufficient, return early
      if (currentAllowance >= amount) {
        console.log(`Allowance already sufficient: ${currentAllowance} >= ${amount}`);
        return "Allowance already sufficient";
      }

      // Send approval transaction
      const hash = await l2Wallet.client.writeContract({
        address: tokenAddress,
        abi: IERC20ABI,
        functionName: 'approve',
        args: [spenderAddress, amount],
        account: l2Wallet.account,
        chain: l2Wallet.publicClient.chain ?? baseSepolia,
      });

      setApprovalHash(hash);

      // Wait for transaction to be mined
      const receipt = await l2Wallet.publicClient.waitForTransactionReceipt({
        hash
      });

      if (receipt.status === 'success') {
        console.log(`Token approval successful: ${hash}`);
        return hash;
      } else {
        throw new Error('Token approval transaction failed on-chain');
      }
    } catch (error) {
      console.error('Error approving token spending:', error);

      // Check if this is a user rejection error
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.log("Token approval rejection detected:", errorMessage);

      if (errorMessage.toLowerCase().includes('rejected') ||
          errorMessage.toLowerCase().includes('denied') ||
          errorMessage.toLowerCase().includes('user refused') ||
          errorMessage.toLowerCase().includes('cancelled') ||
          errorMessage.toLowerCase().includes('declined')) {

        // Important: Reset state FIRST
        setIsApprovingToken(false);
        setApprovalHash(null);

        // Then set the error message
        setError(`Token approval rejected: ${errorMessage}`);

        // Clear error after a short delay
        setTimeout(() => {
          setError(null);
        }, 5000);
      }

      throw error;
    } finally {
      setIsApprovingToken(false);
    }
  };

  // Function to dispatch CCIP transaction
  const dispatchTransaction = async (messageWithSignature: Hex, originalMessage: Hex): Promise<string> => {
    try {
      setIsExecuting(true); // Ensure we set this flag when starting execution

      if (!l2Wallet.client || !l2Wallet.account) {
        throw new Error("Wallet client not available for Base Sepolia");
      }

      // Format token amounts for CCIP
      const formattedTokenAmounts = [
        [
          CHAINLINK_CONSTANTS.baseSepolia.bridgeToken as Address,
          amount
        ] as const
      ];

      // Get fee estimate
      const estimatedFee = await getRouterFeesL2(
        targetContractAddr,
        messageWithSignature,
        amount > 0n ? [{
          token: CHAINLINK_CONSTANTS.baseSepolia.bridgeToken as Address,
          amount: amount
        }] : [],
        BigInt(860_000) // gasLimit
      );

      // Encode the function parameters
      const encodedParams = encodeAbiParameters(
        [
          { type: 'uint64' }, // destinationChainSelector
          { type: 'address' }, // receiverContract
          { type: 'bytes' }, // message
          // `message` is string in the ABI, but force bytes type here as
          // Viem handles string differently than Foundry, and tries
          // to cast bytes to invalid hex strings.
          // TODO: find a way to make Viem behave like Foundry:
          // Solidity:  string(bytes memory messageToEigenlayer)
          // Viem:      toHex(messageToEigenlayer)
          { type: 'tuple[]', components: [
            { type: 'address' }, // token
            { type: 'uint256' } // amount
          ]},
          { type: 'uint256' } // gasLimit
        ],
        [
          BigInt(CHAINLINK_CONSTANTS.ethSepolia.chainSelector),
          RECEIVER_CCIP_ADDRESS,
          messageWithSignature,
          amount > 0n ? formattedTokenAmounts : [],
          BigInt(860_000) // gasLimit
        ]
      );

      // Combine the function selector with the encoded parameters
      // Using SEND_MESSAGE_PAY_NATIVE_SELECTOR (0x7132732a) for sendMessagePayNative
      const data: Hex = `0x${SEND_MESSAGE_PAY_NATIVE_SELECTOR.slice(2)}${encodedParams.slice(2)}`;

      console.log("Sending transaction to CCIP sender contract:", SENDER_CCIP_ADDRESS);

      // Send the transaction
      const hash = await l2Wallet.client.sendTransaction({
        account: l2Wallet.account,
        to: SENDER_CCIP_ADDRESS,
        data: data,
        value: estimatedFee, // send a bit more in case, excess is refunded anyway
        chain: l2Wallet.publicClient.chain ?? baseSepolia,
      });

      console.log("Transaction sent, hash:", hash);

      // Determine transaction type based on the original message
      const txType = (
        targetContractAddr === STRATEGY_MANAGER_ADDRESS ? 'deposit' :
        originalMessage.startsWith(QUEUE_WITHDRAWAL_SELECTOR) ? 'withdrawal' :
        originalMessage.startsWith(COMPLETE_WITHDRAWAL_SELECTOR) ? 'completeWithdrawal' :
        'other'
      ) as 'deposit' | 'withdrawal' | 'completeWithdrawal' | 'other';

      console.log(`Detected transaction type: ${txType}`);

      // Create a pending transaction entry with properly typed status
      const initialTransaction = {
        txHash: hash,
        messageId: '', // Will be updated when CCIP event is processed
        timestamp: Math.floor(Date.now() / 1000),
        type: txType,
        status: 'pending' as 'pending' | 'confirmed' | 'failed',
        from: l2Wallet.account,
        to: targetContractAddr,
        user: l2Wallet.account
      };

      // Wait for transaction to be mined before adding to history
      // This ensures we don't add failed transactions
      console.log("Waiting for transaction receipt...");
      const receipt = await l2Wallet.publicClient.waitForTransactionReceipt({
        hash
      });

      if (receipt.status === 'success') {
        console.log('Transaction successfully mined! Receipt:', receipt.transactionHash);

        console.log("Adding successful transaction to history:", initialTransaction);
        try {
          // Only add transaction to history if it succeeded
          await addTransaction(initialTransaction);
        } catch (addTxError) {
          console.error("Error adding transaction to history:", addTxError);
          // Continue execution since this is non-critical
        }

        // Watch for CCIP events and update the transaction history
        console.log("Starting CCIP event watcher for transaction:", hash);
        watchCCIPTransaction(
          l2Wallet.publicClient,
          hash,
          l2Wallet.account,
          targetContractAddr,
          txType,
          l2Wallet.account,
          async (ccipTransaction) => {
            if (ccipTransaction) {
              console.log("CCIP transaction data received:", ccipTransaction);

              // Ensure we update transaction with messageId correctly
              if (ccipTransaction.messageId) {
                console.log(`Updating transaction ${hash} with messageId: ${ccipTransaction.messageId}`);

                // Update the transaction with the new data by adding it (replaces existing by txHash)
                try {
                  await addTransaction(ccipTransaction);
                } catch (updateTxError) {
                  console.error("Error updating transaction with CCIP data:", updateTxError);
                }
              } else {
                console.log("No messageId found in CCIP transaction data");
              }
            } else {
              console.warn("CCIP event watcher returned null");
            }
          }
        ).catch(err => {
          console.error('Error watching for CCIP events:', err);
        });

        return hash;
      } else {
        console.error("Transaction failed on-chain");
        throw new Error('Transaction failed on-chain');
      }
    } catch (error) {
      console.error('Error dispatching transaction:', error);
      throw error;
    } finally {
      setIsExecuting(false);
    }
  };

  // Function to execute with a direct message parameter
  const executeWithMessage = async (directMessage: Hex): Promise<void> => {
    setError(null);
    setSignature(null);
    setIsExecuting(true);
    let messageWithSignature: Hex | undefined = undefined;

    try {
      // Step 1: Check that we have eigenAgentInfo
      if (!eigenAgentInfo) {
        setIsExecuting(false);
        throw new Error("EigenAgent info not available. Please connect your wallet and ensure you have a registered agent.");
      }

      // Step 2a: Check if we need to handle token approval
      if (tokenApproval) {
        try {
          console.log(`Checking token allowance for ${tokenApproval.tokenAddress}`);

          setIsApprovingToken(true);

          // Show info toast for token approval
          setInfo("Checking token allowance...");

          // Get current allowance
          const currentAllowance = await checkTokenAllowance(
            tokenApproval.tokenAddress,
            eigenAgentInfo.eigenAgentAddress,
            tokenApproval.spenderAddress
          );

          console.log(`Current allowance: ${currentAllowance}, Amount needed: ${tokenApproval.amount}`);

          // If allowance is not enough, request approval
          if (currentAllowance < tokenApproval.amount) {
            setInfo("Please approve token spending");

            const hash = await approveTokenSpending(
              tokenApproval.tokenAddress,
              tokenApproval.spenderAddress,
              tokenApproval.amount
            );

            setApprovalHash(hash);
            setInfo("Token approval submitted");
          } else {
            setInfo("Token allowance is sufficient");
          }
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

      // Step 2b: Switch to Ethereum Sepolia for signing
      setInfo("Temporarily switching to Ethereum Sepolia for signing...");
      await switchChain(l1Wallet.publicClient.chain?.id ?? 11155111);

      // Wait a moment for the switch to take effect
      await new Promise(resolve => setTimeout(resolve, 1000));

      try {
        // Step 3: Create expiry time
        const expiryTime = BigInt(Math.floor(Date.now()/1000) + (expiryMinutes * 60));

        // Step 4: Sign the message
        setInfo("Please sign the message with your wallet...");
        const result = await signMessageForEigenAgentExecution(
          l1Wallet.client!,
          l1Wallet.account!,
          eigenAgentInfo.eigenAgentAddress,
          targetContractAddr,
          directMessage,
          eigenAgentInfo.execNonce,
          expiryTime
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
            await switchChain(l2Wallet.publicClient.chain?.id ?? 84532);
          } catch (switchBackError) {
            console.error('Error switching back to Base Sepolia:', switchBackError);
          }

          if (onError) onError(signError instanceof Error ? signError : new Error(String(signError)));
          return;
        }

        // For other signature errors, rethrow
        throw signError;
      }

      // Step 5: Switch back to Base Sepolia
      setInfo("Switching back to Base Sepolia...");
      await switchChain(l2Wallet.publicClient.chain?.id ?? 84532);

      // Wait for the switch to complete
      await new Promise(resolve => setTimeout(resolve, 1000));

      try {
        // Step 6: Dispatch the transaction
        if (!messageWithSignature) {
          throw new Error("Failed to generate signature message");
        }

        setInfo("Please confirm the transaction in your wallet...");
        const txHash = await dispatchTransaction(messageWithSignature, directMessage);
        setInfo("Transaction submitted successfully");

        // Call onSuccess if provided
        if (onSuccess) onSuccess(txHash);
      } catch (txError) {
        // Handle transaction rejection
        const errorMessage = txError instanceof Error ? txError.message : String(txError);
        console.log("Transaction rejection detected:", errorMessage);

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
        await switchChain(l2Wallet.publicClient.chain?.id ?? 84532);
      } catch (switchBackError) {
        console.error('Error switching back to Base Sepolia:', switchBackError);
      }

      console.error('Error executing EigenLayer operation:', err);
      const errorMessage = err instanceof Error ? err.message : 'Failed to execute operation';
      console.log("General error handler detected:", errorMessage);

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