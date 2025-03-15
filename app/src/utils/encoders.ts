import { Address, Hex, encodeFunctionData } from 'viem';

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
