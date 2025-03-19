import { Address, Hex, encodeFunctionData } from 'viem';
import { DelegationManagerABI } from '../abis';
import { RewardsMerkleClaim } from '../abis/RewardsCoordinatorTypes';

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

/**
 * Interface representing a Withdrawal struct from DelegationManager
 */
export interface WithdrawalStruct {
  staker: Address;
  delegatedTo: Address;
  withdrawer: Address;
  nonce: bigint;
  startBlock: bigint;
  strategies: Address[];
  scaledShares: bigint[];
}

/**
 * Encodes a completeQueuedWithdrawal call for IDelegationManager
 * TypeScript equivalent of encodeCompleteWithdrawalMsg in Solidity
 *
 * @param withdrawal The Withdrawal struct with withdrawal details
 * @param tokensToWithdraw Array of token addresses to receive from withdrawal
 * @param receiveAsTokens Whether to receive the withdrawal as tokens (true) or shares (false)
 * @returns Encoded function call as a hex string
 */
export function encodeCompleteWithdrawalMsg(
  withdrawal: WithdrawalStruct,
  tokensToWithdraw: Address[],
  receiveAsTokens: boolean
): Hex {
  return encodeFunctionData({
    abi: DelegationManagerABI,
    functionName: 'completeQueuedWithdrawal',
    args: [
      withdrawal,
      tokensToWithdraw,
      receiveAsTokens
    ]
  });
}

/**
 * Encodes a processClaim call for IRewardsCoordinator
 * TypeScript equivalent of the Solidity function:
 *
 * function encodeProcessClaimMsg(
 *     IRewardsCoordinator.RewardsMerkleClaim memory claim,
 *     address recipient
 * ) public pure returns (bytes memory) {
 *     return abi.encodeCall(
 *         IRewardsCoordinator.processClaim,
 *         (claim, recipient)
 *     );
 * }
 *
 * @param claim The RewardsMerkleClaim structure with claim details
 * @param recipient The address that will receive the rewards
 * @returns Encoded function call as a hex string
 */
export function encodeProcessClaimMsg(
  claim: RewardsMerkleClaim,
  recipient: Address
): Hex {
  // Function signature: processClaim((uint32,uint32,bytes,(address,bytes32),uint32[],bytes[],(address,uint256)[]),address)

  // Solidity Structs:
  // struct RewardsMerkleClaim {
  //     uint32 rootIndex;
  //     uint32 earnerIndex;
  //     bytes earnerTreeProof;
  //     EarnerTreeMerkleLeaf earnerLeaf;
  //     uint32[] tokenIndices;
  //     bytes[] tokenTreeProofs;
  //     TokenTreeMerkleLeaf[] tokenLeaves;
  // }
  // struct EarnerTreeMerkleLeaf {
  //     address earner;
  //     bytes32 earnerTokenRoot;
  // }
  // struct TokenTreeMerkleLeaf {
  //     IERC20 token;
  //     uint256 cumulativeEarnings;
  // }

  const abi = [
    {
      name: 'processClaim',
      type: 'function',
      inputs: [
        {
          name: 'claim',
          type: 'tuple',
          components: [
            { name: 'rootIndex', type: 'uint32' },
            { name: 'earnerIndex', type: 'uint32' },
            { name: 'earnerTreeProof', type: 'bytes' },
            {
              name: 'earnerLeaf',
              type: 'tuple',
              components: [
                { name: 'earner', type: 'address' },
                { name: 'earnerTokenRoot', type: 'bytes32' }
              ]
            },
            { name: 'tokenIndices', type: 'uint32[]' },
            { name: 'tokenTreeProofs', type: 'bytes[]' },
            {
              name: 'tokenLeaves',
              type: 'tuple[]',
              components: [
                { name: 'token', type: 'address' },
                { name: 'cumulativeEarnings', type: 'uint256' }
              ]
            }
          ]
        },
        { name: 'recipient', type: 'address' }
      ],
      outputs: [],
      stateMutability: 'nonpayable'
    }
  ] as const;

  // Encode the function call
  return encodeFunctionData({
    abi,
    functionName: 'processClaim',
    args: [claim, recipient]
  });
}
