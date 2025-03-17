import { Address, Hex, encodeFunctionData } from 'viem';
import { DelegationManagerABI } from '../abis';

// Constant for zero address
export const ZeroAddress: Address = "0x0000000000000000000000000000000000000000";

/**
 * Encodes a depositIntoStrategy call for IStrategyManager
 * TypeScript equivalent of the Solidity function:
 *
 * function encodeDepositIntoStrategyMsg(
 *     address strategy,
 *     address token,
 *     uint256 amount
 * ) public pure returns (bytes memory) {
 *     return abi.encodeWithSelector(
 *         IStrategyManager.depositIntoStrategy.selector,
 *         strategy,
 *         token,
 *         amount
 *     );
 * }
 *
 * @param strategy The strategy address
 * @param token The token address
 * @param amount The amount to deposit
 * @returns Encoded function call as a hex string
 */
export function encodeDepositIntoStrategyMsg(
  strategy: Address,
  token: Address,
  amount: bigint
): Hex {
  // Function signature: depositIntoStrategy(address,address,uint256)
  const abi = [
    {
      name: 'depositIntoStrategy',
      type: 'function',
      inputs: [
        { name: 'strategy', type: 'address' },
        { name: 'token', type: 'address' },
        { name: 'amount', type: 'uint256' }
      ],
      outputs: [
        { name: 'shares', type: 'uint256' }
      ],
      stateMutability: 'nonpayable'
    }
  ] as const;

  // Encode the function call
  return encodeFunctionData({
    abi,
    functionName: 'depositIntoStrategy',
    args: [strategy, token, amount]
  });
}

/**
 * Encodes a queueWithdrawals call for IDelegationManager
 * TypeScript equivalent of the Solidity function that creates a QueuedWithdrawalParams struct
 * and calls queueWithdrawals.
 *
 * @param strategy The strategy address
 * @param shares The amount of shares to withdraw
 * @param withdrawer The address that will be able to claim the withdrawal (deprecated but still required)
 * @returns Encoded function call as a hex string
 */
export function encodeQueueWithdrawalMsg(
  strategy: Address,
  shares: bigint,
  withdrawer: Address
): Hex {

  // Create a single withdrawal parameter
  const queuedWithdrawalParams = [
    {
      strategies: [strategy],
      depositShares: [shares],
      __deprecated_withdrawer: withdrawer // Still required by the struct despite being deprecated
    }
  ];

  // Encode the function call
  return encodeFunctionData({
    abi: DelegationManagerABI,
    functionName: 'queueWithdrawals',
    args: [queuedWithdrawalParams]
  });
}
