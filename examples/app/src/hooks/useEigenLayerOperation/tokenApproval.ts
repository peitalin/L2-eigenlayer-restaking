import { Address } from 'viem';
import { TokenApproval } from '../../types';
import { IERC20ABI } from '../../abis';
import { checkTokenAllowance } from './utils';


interface TokenApprovalResponse {
  hash: string;
  message: string;
}

/**
 * Approve token spending
 */
export async function approveTokenSpending(
  l2Wallet: any, // Using 'any' to avoid type conflicts
  tokenAddress: Address,
  spenderAddress: Address,
  amount: bigint
): Promise<TokenApprovalResponse> {
  try {
    if (!l2Wallet.client || !l2Wallet.account) {
      throw new Error("Wallet client not available for Base Sepolia");
    }

    // Check current allowance first
    const currentAllowance = await checkTokenAllowance(
      l2Wallet,
      tokenAddress,
      l2Wallet.account,
      spenderAddress
    );

    // If allowance is already sufficient, return early
    if (currentAllowance >= amount) {
      console.log(`Allowance already sufficient: ${currentAllowance} >= ${amount}`);
      return {
        hash: "",
        message: "Allowance already sufficient"
      }
    }

    // Send approval transaction
    const hash = await l2Wallet.client.writeContract({
      address: tokenAddress,
      abi: IERC20ABI,
      functionName: 'approve',
      args: [spenderAddress, amount],
      account: l2Wallet.account,
      chain: l2Wallet.publicClient?.chain,
    });

    // Wait for transaction to be mined
    const receipt = await l2Wallet.publicClient?.waitForTransactionReceipt({
      hash
    });

    if (receipt?.status === 'success') {
      console.log(`Token approval successful: ${hash}`);
      return {
        hash: hash,
        message: "Allowance increased"
      }
    } else {
      throw new Error('Token approval transaction failed on-chain');
    }
  } catch (error) {
    console.error('Error approving token spending:', error);

    // Check if this is a user rejection error
    const errorMessage = error instanceof Error ? error.message : 'Unknown error';
    console.log("Token approval error:", errorMessage);

    throw error;
  }
}

/**
 * Handle token approval process
 */
export async function handleTokenApproval(
  l2Wallet: any, // Using 'any' to avoid type conflicts
  tokenApproval: TokenApproval | undefined,
  ownerAddress: Address
): Promise<TokenApprovalResponse> {
  if (!tokenApproval) {
    return {
      hash: "",
      message: "No token approval provided"
    }
  };

  console.log(`Checking token allowance for ${tokenApproval.tokenAddress}`);

  // Get current allowance
  const currentAllowance = await checkTokenAllowance(
    l2Wallet,
    tokenApproval.tokenAddress,
    ownerAddress,
    tokenApproval.spenderAddress
  );

  console.log(`Current allowance: ${currentAllowance}, Amount needed: ${tokenApproval.amount}`);

  // If allowance is not enough, request approval
  if (currentAllowance < tokenApproval.amount) {
    return await approveTokenSpending(
      l2Wallet,
      tokenApproval.tokenAddress,
      tokenApproval.spenderAddress,
      tokenApproval.amount
    );
  } else {
    return {
      hash: "",
      message: "Allowance already sufficient"
    }
  }
}