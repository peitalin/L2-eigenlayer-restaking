import { Address, Hex, encodeAbiParameters } from 'viem';
import {
  SENDER_HOOKS_ADDRESS,
  RECEIVER_CCIP_ADDRESS,
  EthSepolia,
  BaseSepolia
} from '../../addresses';
import { SenderHooksABI, IERC20ABI } from '../../abis';
import { TransactionType } from '../../types';

// Function selectors for EigenLayer operations
export const FUNCTION_SELECTORS = {
  SEND_MESSAGE_PAY_NATIVE: '0x7132732a' as Hex, // sendMessagePayNative(uint64,address,bytes,tuple[],uint256)
  DEPOSIT: '0xe7a050aa' as Hex, // deposit(address,address,uint256)
  QUEUE_WITHDRAWAL: '0x0dd8dd02' as Hex, // queueWithdrawals((address[],uint256[],address)[])
  COMPLETE_WITHDRAWAL: '0xe4cc3f90' as Hex, // completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],bool)
  PROCESS_CLAIM: '0x3ccc861d' as Hex, // processClaim(bytes32,address)
  DELEGATE_TO: '0xeea9064b' as Hex, // delegateTo(address,(bytes,uint256),bytes32)
  UNDELEGATE: '0xda8be864' as Hex, // undelegate(address)
  MINT_EIGEN_AGENT: '0xcc15a557' as Hex, // mintEigenAgent(bytes)
};

/**
 * Check token allowance for a given token, owner, and spender
 */
export async function checkTokenAllowance(
  l2Wallet: any, // Using 'any' to avoid type conflicts
  tokenAddress: Address,
  ownerAddress: Address,
  spenderAddress: Address
): Promise<bigint> {
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
}

/**
 * Get gas limit for a specific function selector from SenderHooks contract
 */
export async function getGasLimitFromSenderHooks(
  l2Wallet: any, // Using 'any' to avoid type conflicts
  functionSelector: Hex
): Promise<bigint> {
  try {
    if (!l2Wallet.publicClient) {
      throw new Error("Public client not available for Base Sepolia");
    }

    // Extract the first 4 bytes (function selector) if a full message is provided
    const selector = functionSelector.length > 10
      ? `0x${functionSelector.slice(2, 10)}` as Hex
      : functionSelector;

    const gasLimit = await l2Wallet.publicClient.readContract({
      address: SENDER_HOOKS_ADDRESS,
      abi: SenderHooksABI,
      functionName: 'getGasLimitForFunctionSelector',
      args: [selector]
    });

    console.log(`Gas limit from SenderHooks for selector ${selector}: ${gasLimit}`);
    return gasLimit as bigint;
  } catch (error) {
    console.error('Error getting gas limit from SenderHooks:', error);
    // Return a default gas limit as fallback
    return BigInt(300000);
  }
}

/**
 * Encode CCIP message for cross-chain communication
 */
export function encodeCcipMessage(
  messageWithSignature: Hex,
  amount: bigint,
  txGasLimit: bigint
): Hex {
  // Format token amounts for CCIP
  const formattedTokenAmounts = [
    [
      BaseSepolia.bridgeToken as Address,
      amount
    ] as const
  ];

  // Encode the function parameters
  const encodedParams = encodeAbiParameters(
    [
      { type: 'uint64' }, // destinationChainSelector
      { type: 'address' }, // receiverContract
      { type: 'bytes' }, // message
      { type: 'tuple[]', components: [
        { type: 'address' }, // token
        { type: 'uint256' } // amount
      ]},
      { type: 'uint256' } // gasLimit
    ],
    [
      BigInt(EthSepolia.chainSelector || '0'),
      RECEIVER_CCIP_ADDRESS,
      messageWithSignature,
      amount > 0n ? formattedTokenAmounts : [],
      txGasLimit
    ]
  );

  // Combine the function selector with the encoded parameters
  // Using SEND_MESSAGE_PAY_NATIVE_SELECTOR for sendMessagePayNative
  return `0x${FUNCTION_SELECTORS.SEND_MESSAGE_PAY_NATIVE.slice(2)}${encodedParams.slice(2)}` as Hex;
}

/**
 * Detect transaction type from message
 */
export function detectTransactionType(message: Hex): TransactionType {
  if (!message) return 'other';

  const selector = message.slice(0, 10);

  switch (selector) {
    case FUNCTION_SELECTORS.DEPOSIT:
      return 'deposit';
    case FUNCTION_SELECTORS.QUEUE_WITHDRAWAL:
      return 'queueWithdrawal';
    case FUNCTION_SELECTORS.COMPLETE_WITHDRAWAL:
      return 'completeWithdrawal';
    case FUNCTION_SELECTORS.DELEGATE_TO:
      return 'delegateTo';
    case FUNCTION_SELECTORS.UNDELEGATE:
      return 'undelegate';
    case FUNCTION_SELECTORS.PROCESS_CLAIM:
      return 'processClaim';
    default:
      return 'other';
  }
}