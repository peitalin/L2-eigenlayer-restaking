import { useState } from 'react';
import { Address, Hex, formatEther, encodeAbiParameters } from 'viem';
import { baseSepolia } from '../hooks/useClients';
import { useClientsContext } from '../contexts/ClientsContext';
import { signMessageForEigenAgentExecution } from '../utils/signers';
import { CHAINLINK_CONSTANTS, SENDER_CCIP_ADDRESS } from '../addresses';
import { getRouterFeesL2 } from '../utils/routerFees';
import { RECEIVER_CCIP_ADDRESS } from '../addresses/ethSepoliaContracts';
import { IERC20ABI } from '../abis';

type TokenApproval = {
  tokenAddress: Address;
  spenderAddress: Address;
  amount: bigint;
}

interface EigenLayerOperationConfig {
  // Target for the EigenAgent to call on L1
  targetContractAddr: Address;
  // Encoded call data for the target contract
  messageToEigenlayer: Hex;
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
  execute: () => Promise<void>;
  isExecuting: boolean;
  signature: Hex | null;
  error: string | null;
  isApprovingToken: boolean;
  approvalHash: string | null;
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
  messageToEigenlayer,
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

  const [isExecuting, setIsExecuting] = useState(false);
  const [signature, setSignature] = useState<Hex | null>(null);
  const [error, setError] = useState<string | null>(null);
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
      throw error;
    } finally {
      setIsApprovingToken(false);
    }
  };

  // Function to dispatch CCIP transaction
  const dispatchTransaction = async (messageWithSignature: Hex): Promise<string> => {
    try {
      if (!l2Wallet.client || !l2Wallet.account) {
        throw new Error("Wallet client not available for Base Sepolia");
      }

      // Function selector for sendMessagePayNative
      const functionSelector = '0x7132732a' as Hex;

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
      const data: Hex = `0x${functionSelector.slice(2)}${encodedParams.slice(2)}`;

      // Send the transaction
      const hash = await l2Wallet.client.sendTransaction({
        account: l2Wallet.account,
        to: SENDER_CCIP_ADDRESS,
        data: data,
        value: estimatedFee,
        chain: l2Wallet.publicClient.chain ?? baseSepolia,
      });

      // Wait for transaction to be mined
      const receipt = await l2Wallet.publicClient.waitForTransactionReceipt({
        hash
      });

      if (receipt.status === 'success') {
        console.log('Transaction successfully mined! Request has been sent to L1.');
        return hash;
      } else {
        throw new Error('Transaction failed on-chain');
      }
    } catch (error) {
      console.error('Error dispatching transaction:', error);
      throw error;
    }
  };

  // Main execution function
  const execute = async (): Promise<void> => {
    // Ensure we have all required information
    if (!eigenAgentInfo?.eigenAgentAddress || !l1Wallet.account || !l2Wallet.account) {
      setError("EigenAgent information or wallet not connected");
      return;
    }

    try {
      setIsExecuting(true);

      // Step 1: Approve token spending if needed
      if (tokenApproval) {
        try {
          setError(`Approving ${formatEther(tokenApproval.amount)} tokens...`);
          await approveTokenSpending(
            tokenApproval.tokenAddress,
            tokenApproval.spenderAddress,
            tokenApproval.amount
          );
        } catch (approvalError) {
          setError(`Token approval failed: ${approvalError instanceof Error ? approvalError.message : 'Unknown error'}`);
          if (onError) onError(new Error(`Token approval failed: ${approvalError}`));
          return;
        }
      }

      // Step 2: Switch to Ethereum Sepolia for signing
      setError("Temporarily switching to Ethereum Sepolia for signing...");
      await switchChain(l1Wallet.publicClient.chain?.id ?? 11155111);

      // Wait a moment for the switch to take effect
      await new Promise(resolve => setTimeout(resolve, 1000));

      // Verify L1 client is available
      if (!l1Wallet.client) {
        throw new Error("Wallet client not available for Sepolia");
      }

      // Step 3: Create expiry time
      const expiryTime = BigInt(Math.floor(Date.now()/1000) + (expiryMinutes * 60));

      // Step 4: Sign the message
      const { signature: sig, messageWithSignature } = await signMessageForEigenAgentExecution(
        l1Wallet.client,
        l1Wallet.account,
        eigenAgentInfo.eigenAgentAddress,
        targetContractAddr,
        messageToEigenlayer,
        eigenAgentInfo.execNonce,
        expiryTime
      );

      setSignature(sig);

      // Step 5: Switch back to Base Sepolia
      setError("Switching back to Base Sepolia...");
      await switchChain(l2Wallet.publicClient.chain?.id ?? 84532);

      // Wait for the switch to complete
      await new Promise(resolve => setTimeout(resolve, 1000));
      setError(null);

      // Step 6: Dispatch the transaction
      const txHash = await dispatchTransaction(messageWithSignature);

      // Call onSuccess if provided
      if (onSuccess) onSuccess(txHash);

    } catch (err) {
      // Make sure we always switch back to Base Sepolia if there's an error
      try {
        await switchChain(l2Wallet.publicClient.chain?.id ?? 84532);
      } catch (switchBackError) {
        console.error('Error switching back to Base Sepolia:', switchBackError);
      }

      console.error('Error executing EigenLayer operation:', err);
      setError(err instanceof Error ? err.message : 'Failed to execute operation');

      if (onError) onError(err instanceof Error ? err : new Error(String(err)));
    } finally {
      setIsExecuting(false);
    }
  };

  return {
    execute,
    isExecuting,
    signature,
    error,
    isApprovingToken,
    approvalHash
  };
}