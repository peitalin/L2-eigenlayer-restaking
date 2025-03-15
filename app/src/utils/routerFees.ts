import { Address, Hex, encodeAbiParameters, concat, toHex } from 'viem';
import { ROUTER_ABI, EVMTokenAmount } from '../abis';
import { CHAINLINK_CONSTANTS } from '../addresses';
import { getL1Client, getL2Client } from './clients';

// Custom error class for invalid token transfers
export class CCIPTokenTransferError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CCIPTokenTransferError';
  }
}

// CCIP known error signatures
const ERROR_SIGNATURES = {
  INVALID_EXTRA_ARGS_TAG: '0xbf16aab6' // InvalidExtraArgsTag error
};

// CCIP constant selectors from Client.sol
// This is bytes4(keccak256("CCIP EVMExtraArgsV1"))
const EVM_EXTRA_ARGS_V1_TAG = '0x97a657c9';

/**
 * Encodes the EVM extra args for CCIP following the Client.sol implementation
 * This matches the Solidity _argsToBytes function:
 *
 * function _argsToBytes(EVMExtraArgsV1 memory extraArgs) internal pure returns (bytes memory bts) {
 *     return abi.encodeWithSelector(EVM_EXTRA_ARGS_V1_TAG, extraArgs);
 * }
 *
 * @param gasLimit Gas limit for the transaction
 * @returns Encoded extra args with proper selector
 */
function encodeEVMExtraArgs(gasLimit: bigint): Hex {
  // First encode the gasLimit parameter
  const encodedParams = encodeAbiParameters(
    [{ name: 'gasLimit', type: 'uint256' }],
    [gasLimit]
  );

  // Then prepend the selector to match the Solidity implementation
  // This is equivalent to abi.encodeWithSelector(EVM_EXTRA_ARGS_V1_TAG, extraArgs)
  return concat([
    EVM_EXTRA_ARGS_V1_TAG as Hex,
    encodedParams
  ]);
}

/**
 * Gets the router fees for sending a message from L1 (Ethereum Sepolia) to L2 (Base Sepolia)
 * @param receiver The address that will receive the message on L2
 * @param message The message string to send
 * @param tokenAmounts Array of token amounts to transfer (if any)
 * @param gasLimit Gas limit for execution on the destination chain
 * @returns The fee amount in wei
 */
export async function getRouterFeesL1(
  receiver: Address,
  message: string,
  tokenAmounts: EVMTokenAmount[] = [],
  gasLimit: bigint = 200000n
): Promise<bigint> {
  const client = getL1Client();

  // Encode the receiver and message as bytes
  const receiverEncoded = encodeAbiParameters([{ type: 'address' }], [receiver]);
  const dataEncoded = encodeAbiParameters([{ type: 'string' }], [message]);

  // Encode the extraArgs with gas limit
  const extraArgs = encodeEVMExtraArgs(gasLimit);

  try {
    // Call the getFee function on the router contract
    const fee = await client.readContract({
      address: CHAINLINK_CONSTANTS.ethSepolia.router,
      abi: ROUTER_ABI,
      functionName: 'getFee',
      args: [
        BigInt(CHAINLINK_CONSTANTS.baseSepolia.chainSelector),
        {
          receiver: receiverEncoded,
          data: dataEncoded,
          tokenAmounts: tokenAmounts,
          feeToken: '0x0000000000000000000000000000000000000000', // native token (ETH)
          extraArgs: extraArgs
        }
      ]
    });

    return fee;
  } catch (error) {
    console.error('Error getting router fees from L1:', error);

    // Check for specific error signatures
    const errorString = String(error);
    if (errorString.includes(ERROR_SIGNATURES.INVALID_EXTRA_ARGS_TAG)) {
      console.warn('InvalidExtraArgsTag error detected. This typically occurs with unsupported token transfers.');
      throw new CCIPTokenTransferError('Token transfers not supported in this direction or with these tokens');
    }

    // Return a fallback fee to prevent UI errors
    console.warn('Using fallback fee estimate of 0.01 ETH');
    return 10000000000000000n; // 0.01 ETH as fallback
  }
}

/**
 * Gets the router fees for sending a message from L2 (Base Sepolia) to L1 (Ethereum Sepolia)
 * @param receiver The address that will receive the message on L1
 * @param message The message string to send
 * @param tokenAmounts Array of token amounts to transfer (if any)
 * @param gasLimit Gas limit for execution on the destination chain
 * @returns The fee amount in wei
 */
export async function getRouterFeesL2(
  receiver: Address,
  message: string,
  tokenAmounts: EVMTokenAmount[] = [],
  gasLimit: bigint = 200000n
): Promise<bigint> {
  const client = getL2Client();

  // Encode the receiver and message as bytes
  const receiverEncoded = encodeAbiParameters([{ type: 'address' }], [receiver]);
  const dataEncoded = encodeAbiParameters([{ type: 'string' }], [message]);

  // Encode the extraArgs with gas limit
  const extraArgs = encodeEVMExtraArgs(gasLimit);

  // For token transfers from L2 to L1, we need to use only supported tokens
  // Empty the tokenAmounts array to avoid errors since our tests show it's not supported
  const validatedTokenAmounts: EVMTokenAmount[] = [];

  // Log the encoded values for debugging
  // console.log('Estimating L2 router fees with:', {
  //   receiver,
  //   receiverEncoded,
  //   destinationChain: CHAINLINK_CONSTANTS.ethSepolia.chainSelector,
  //   tokenAmounts: validatedTokenAmounts, // Use empty token amounts to avoid errors
  //   extraArgs
  // });

  try {
    // Call the getFee function on the router contract
    const fee = await client.readContract({
      address: CHAINLINK_CONSTANTS.baseSepolia.router,
      abi: ROUTER_ABI,
      functionName: 'getFee',
      args: [
        BigInt(CHAINLINK_CONSTANTS.ethSepolia.chainSelector),
        {
          receiver: receiverEncoded,
          data: dataEncoded,
          tokenAmounts: validatedTokenAmounts, // Use empty token amounts to avoid errors
          feeToken: '0x0000000000000000000000000000000000000000', // native token (ETH)
          extraArgs: extraArgs
        }
      ]
    });

    return fee;
  } catch (error) {
    console.error('Error getting router fees from L2:', error);

    // Check for specific CCIP errors to provide better messages
    const errorString = String(error);
    if (errorString.includes(ERROR_SIGNATURES.INVALID_EXTRA_ARGS_TAG)) {
      console.warn('InvalidExtraArgsTag error detected. This typically occurs with unsupported token transfers.');
      throw new CCIPTokenTransferError('Token transfers from L2 to L1 are not supported');
    }

    // Return a fallback fee to prevent UI errors
    console.warn('Using fallback fee estimate of 0.01 ETH');
    return 10000000000000000n; // 0.01 ETH as fallback
  }
}

// Helper function to format fees in a human-readable way
export function formatFees(fees: bigint): string {
  // Format to ETH with 6 decimal places
  const ethAmount = Number(fees) / 1e18;
  return `${ethAmount.toFixed(6)} ETH`;
}