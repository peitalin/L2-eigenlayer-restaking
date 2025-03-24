import { Address, Hex, TransactionReceipt } from 'viem';
import { BaseSepolia, SENDER_CCIP_ADDRESS } from '../../addresses';
import { getRouterFeesL2 } from '../../utils/routerFees';
import { getGasLimitFromSenderHooks, encodeCcipMessage, detectTransactionType } from './utils';

/**
 * Sleep for a specified number of milliseconds
 */
const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

/**
 * Dispatch a cross-chain transaction using CCIP
 */
export async function dispatchTransaction(
  l2Wallet: any, // Using 'any' to avoid type conflicts
  targetContractAddr: Address,
  messageWithSignature: Hex,
  originalMessage: Hex,
  amount: bigint,
  customGasLimit?: bigint,
  setInfo?: (info: string) => void
): Promise<{ txHash: `0x${string}`; receipt: TransactionReceipt }> {
  if (!l2Wallet.client || !l2Wallet.account) {
    throw new Error("Wallet client not available for Base Sepolia");
  }

  // Use custom gas limit if provided, otherwise use default
  let txGasLimit: bigint;
  if (customGasLimit) {
    txGasLimit = customGasLimit;
  } else {
    // Extract the function selector from the original message
    const selector = originalMessage.slice(0, 10) as Hex;
    txGasLimit = await getGasLimitFromSenderHooks(l2Wallet, selector);
  }
  console.log("txGasLimit", txGasLimit);

  // Get fee estimate
  const estimatedFee = await getRouterFeesL2(
    targetContractAddr,
    messageWithSignature,
    amount > 0n ? [{
      token: BaseSepolia.bridgeToken as Address,
      amount: amount
    }] : [],
    txGasLimit
  );

  // Encode the CCIP message
  const data = encodeCcipMessage(messageWithSignature, amount, txGasLimit);

  console.log("Sending transaction to CCIP sender contract:", SENDER_CCIP_ADDRESS);

  // Retry configuration
  const maxRetries = 5;
  let retryCount = 0;
  let txHash: `0x${string}` | undefined;

  // Retry loop with exponential backoff
  while (retryCount <= maxRetries) {
    try {
      // Send the transaction
      txHash = await l2Wallet.client.sendTransaction({
        account: l2Wallet.account,
        to: SENDER_CCIP_ADDRESS,
        data: data,
        value: estimatedFee, // send a bit more in case, excess is refunded anyway
        chain: l2Wallet.publicClient?.chain,
      });

      console.log("Transaction sent, hash:", txHash);
      break; // Success, exit the loop
    } catch (error: any) {
      // Check if it's a rate limit error
      const isRateLimit =
        error?.message?.includes('429') ||
        error?.details?.includes('429') ||
        error?.cause?.message?.includes('429') ||
        error?.cause?.details?.includes('429');

      // If we've reached max retries or it's not a rate limit error, throw
      if (retryCount >= maxRetries || !isRateLimit) {
        if (isRateLimit) {
          throw new Error("RPC endpoint rate limit exceeded. Please try again in a few minutes.");
        }
        throw error;
      }

      // Exponential backoff with jitter
      const delay = Math.min(1000 * (2 ** retryCount) + Math.random() * 1000, 30000);
      console.log(`Rate limit hit. Retrying in ${Math.round(delay / 1000)} seconds... (Attempt ${retryCount + 1}/${maxRetries})`);

      if (setInfo) {
        setInfo(`RPC rate limit hit. Retrying in ${Math.round(delay / 1000)} seconds... (${retryCount + 1}/${maxRetries})`);
      }

      await sleep(delay);
      retryCount++;
    }
  }

  if (!txHash) {
    throw new Error("Failed to send transaction after multiple retries");
  }

  const txType = detectTransactionType(originalMessage);
  console.log(`Detected transaction type: ${txType}`);

  // Wait for transaction to be mined
  console.log("Waiting for transaction receipt...");

  // Set info state with message about sending to L1
  if (setInfo) {
    setInfo("Sending message to L1 Ethereum...");
  }

  try {
    const receipt = await l2Wallet.publicClient?.waitForTransactionReceipt({
      hash: txHash
    });

    if (receipt?.status === 'success') {
      console.log('Transaction successfully mined! Receipt:', receipt.transactionHash);
      return {
        txHash: txHash,
        receipt: receipt
      };
    } else {
      console.error("Transaction failed on-chain");
      throw new Error('Transaction failed on-chain');
    }
  } catch (error: any) {
    // Check for rate limit errors in receipt fetching
    if (error?.message?.includes('429') ||
        error?.details?.includes('429') ||
        error?.cause?.message?.includes('429') ||
        error?.cause?.details?.includes('429')) {
      throw new Error("RPC endpoint rate limit exceeded while waiting for receipt. Your transaction may still be processing. Please check the transaction hash on the explorer.");
    }
    throw error;
  }
}