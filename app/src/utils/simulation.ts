import { Address, Hex, keccak256, encodeAbiParameters, toHex, encodePacked } from 'viem';
import { publicClients } from '../hooks/useClients';
import { StrategyManagerABI, DelegationManagerABI } from '../abis';
import { EthSepolia, BaseSepolia, DELEGATION_MANAGER_ADDRESS, STRATEGY_MANAGER_ADDRESS } from '../addresses';

/**
 * Simulates a call to the DelegationManager's delegateTo function
 * This helps verify if the delegation would succeed before actually submitting the transaction
 *
 * @param operator The operator address to delegate to
 * @param signatureWithExpiry The signature struct containing signature and expiry
 * @param salt The salt used for the delegation approval
 * @param staker The staker address (sender of the transaction)
 * @param publicClient The Ethereum public client
 * @returns Result of the simulation (success/failure and any error message)
 */
export async function simulateDelegateTo(
  operator: Address,
  signatureWithExpiry: { signature: Hex, expiry: bigint },
  salt: Hex,
  staker: Address
): Promise<{ success: boolean, error?: string }> {
  try {
    // First verify the contract exists on Eth Sepolia public client
    const sepoliaPublicClient = publicClients[11155111]; // Sepolia chain ID
    const code = await sepoliaPublicClient.getCode({ address: STRATEGY_MANAGER_ADDRESS });
    if (!code) {
      throw new Error(`No contract code found at ${STRATEGY_MANAGER_ADDRESS}`);
    }
    console.log("Simulating delegateTo with parameters:");
    console.log("operator:", operator);
    console.log("staker:", staker);
    console.log("salt:", salt);
    console.log("expiry:", signatureWithExpiry.expiry.toString());
    console.log("signature:", signatureWithExpiry.signature);

    // Simulate the call using eth_call
    const result = await sepoliaPublicClient.simulateContract({
      address: DELEGATION_MANAGER_ADDRESS,
      abi: DelegationManagerABI,
      functionName: 'delegateTo',
      args: [
        operator,
        {
          signature: signatureWithExpiry.signature,
          expiry: signatureWithExpiry.expiry
        },
        salt
      ],
      account: staker
    });

    console.log("Simulation successful:", result);
    return { success: true };
  } catch (error: any) {
    console.error('Error simulating delegateTo:', error);
    // Extract the revert reason if available
    let errorMessage = 'Failed to simulate delegateTo';
    if (error.cause?.reason) {
      errorMessage = error.cause.reason;
    } else if (error.message) {
      errorMessage = error.message;
    }

    return {
      success: false,
      error: errorMessage
    };
  }
}

/**
 * Simulates a call to the StrategyManager's depositIntoStrategy function
 * This helps verify if the deposit would succeed before actually submitting the transaction
 *
 * @param strategy The strategy address to deposit into
 * @param token The token address to deposit
 * @param amount The amount to deposit
 * @param staker The staker address (sender of the transaction)
 * @param publicClient The Ethereum public client
 * @returns Result of the simulation (success/failure and any error message)
 */
export async function simulateDepositIntoStrategy(
  strategy: Address,
  token: Address,
  amount: bigint,
  staker: Address,
): Promise<{ success: boolean, error?: string, request?: any }> {
  try {
    // First verify the contract exists on Eth Sepolia public client
    const sepoliaPublicClient = publicClients[11155111]; // Sepolia chain ID
    const code = await sepoliaPublicClient.getCode({ address: STRATEGY_MANAGER_ADDRESS });
    if (!code) {
      throw new Error(`No contract code found at ${STRATEGY_MANAGER_ADDRESS}`);
    }

    console.log("\nSimulating depositIntoStrategy with parameters:");
    console.log("strategy:", strategy);
    console.log("token:", token);
    console.log("amount:", amount.toString());
    console.log("staker:", staker);
    console.log("STRATEGY_MANAGER_ADDRESS:", STRATEGY_MANAGER_ADDRESS);

    // For ERC20 tokens, the balances are typically stored at slot 0
    // For an address in a mapping, the slot is keccak256(abi.encode(address, uint256))
    const balanceMappingSlot = 0n;
    const balanceSlot = keccak256(
      encodeAbiParameters(
        [{ type: 'address' }, { type: 'uint256' }],
        [staker, balanceMappingSlot]
      )
    );

    // For allowances, it's typically a double mapping at slot 1
    // mapping(address => mapping(address => uint256)) at slot 1
    const allowanceMappingSlot = 1n;

    // First level of mapping: owner address -> mapping
    const firstLevelSlot = keccak256(
      encodeAbiParameters(
        [{ type: 'address' }, { type: 'uint256' }],
        [staker, allowanceMappingSlot]
      )
    );

    // Second level of mapping: first level result -> spender address
    const allowanceSlot = keccak256(
      encodeAbiParameters(
        [{ type: 'address' }, { type: 'bytes32' }],
        [STRATEGY_MANAGER_ADDRESS, firstLevelSlot]
      )
    );

    // Set simulated balance and allowance to be twice the amount
    const simulatedBalance = amount * 2n;
    const simulatedAllowance = amount * 2n;

    // Convert to hex with proper padding
    const balanceHex = toHex(simulatedBalance, { size: 32 });
    const allowanceHex = toHex(simulatedAllowance, { size: 32 });

    console.log("\nStorage override details:");
    console.log("Balance mapping slot:", balanceMappingSlot.toString());
    console.log("Balance slot:", balanceSlot);
    console.log("First level allowance slot:", firstLevelSlot);
    console.log("Final allowance slot:", allowanceSlot);
    console.log("Simulated balance (hex):", balanceHex);
    console.log("Simulated allowance (hex):", allowanceHex);

    // Simulate the call using eth_call with state override
    const result = await sepoliaPublicClient.simulateContract({
      address: STRATEGY_MANAGER_ADDRESS,
      abi: StrategyManagerABI,
      functionName: 'depositIntoStrategy',
      args: [strategy, token, amount],
      account: staker,
      // Override both the token balance and allowance in the simulation
      stateOverride: [
        {
          // The token contract
          address: token,
          stateDiff: [
            {
              slot: balanceSlot,
              value: balanceHex
            },
            {
              slot: allowanceSlot,
              value: allowanceHex
            },
          ],
        },
      ],
    });

    console.log("\nSimulation result:", result);
    return { success: true, request: result.request };
  } catch (error: any) {
    console.error('Error simulating depositIntoStrategy:', error);
    // Extract the revert reason if available
    let errorMessage = 'Failed to simulate deposit';
    if (error.cause?.reason) {
      errorMessage = error.cause.reason;
    } else if (error.message) {
      errorMessage = error.message;
    }

    return {
      success: false,
      error: errorMessage
    };
  }
}

/**
 * Simulates a call to the DelegationManager's queueWithdrawals function
 * This helps verify if the withdrawal queuing would succeed before actually submitting the transaction
 *
 * @param strategy The strategy address to withdraw from
 * @param shares The amount of shares to withdraw
 * @param staker The staker and withdrawer address
 * @param publicClient The Ethereum public client
 * @returns Result of the simulation (success/failure and any error message)
 */
export async function simulateQueueWithdrawal(
  strategy: Address,
  shares: bigint,
  staker: Address,
): Promise<{ success: boolean, error?: string }> {
  try {
    // First verify the contract exists on Eth Sepolia public client
    const sepoliaPublicClient = publicClients[11155111]; // Sepolia chain ID
    const code = await sepoliaPublicClient.getCode({ address: STRATEGY_MANAGER_ADDRESS });
    if (!code) {
      throw new Error(`No contract code found at ${STRATEGY_MANAGER_ADDRESS}`);
    }
    console.log("Simulating queueWithdrawals with parameters:");
    console.log("strategy:", strategy);
    console.log("shares:", shares.toString());
    console.log("staker:", staker);

    // Create the params for queueWithdrawals
    const queuedWithdrawalParams = [{
      strategies: [strategy],
      depositShares: [shares],
      __deprecated_withdrawer: staker
    }];

    // For StrategyManager, the deposits are stored in a mapping at a specific slot
    // Calculate the derived slot for the staker's shares in this strategy
    // This is a simplification; in a real implementation you'd need the exact storage layout
    const sharesSlot = keccak256(
      encodePacked(
        ['address', 'address', 'uint256'],
        [staker, strategy, 2n] // 2 is a hypothetical slot for the shares mapping
      )
    );

    // Simulate the call using eth_call with state override
    const result = await sepoliaPublicClient.simulateContract({
      address: DELEGATION_MANAGER_ADDRESS,
      abi: [
        {
          name: 'queueWithdrawals',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            {
              name: 'params',
              type: 'tuple[]',
              components: [
                { name: 'strategies', type: 'address[]' },
                { name: 'depositShares', type: 'uint256[]' },
                { name: '__deprecated_withdrawer', type: 'address' }
              ]
            }
          ],
          outputs: [{ name: '', type: 'bytes32[]' }]
        }
      ],
      functionName: 'queueWithdrawals',
      args: [queuedWithdrawalParams],
      account: staker,
      // Override the shares balance in the simulation
      stateOverride: [
        {
          // The StrategyManager contract
          address: STRATEGY_MANAGER_ADDRESS,
          stateDiff: [
            {
              // The slot for the staker's shares in this strategy
              slot: sharesSlot,
              // A large enough balance (twice the withdrawal amount)
              value: `0x${(shares * 2n).toString(16).padStart(64, '0')}`,
            },
          ],
        },
      ],
    });

    console.log("Simulation successful:", result);
    return { success: true };
  } catch (error: any) {
    console.error('Error simulating queueWithdrawals:', error);
    // Extract the revert reason if available
    let errorMessage = 'Failed to simulate queue withdrawal';
    if (error.cause?.reason) {
      errorMessage = error.cause.reason;
    } else if (error.message) {
      errorMessage = error.message;
    }

    return {
      success: false,
      error: errorMessage
    };
  }
}

/**
 * Simulates a call to the DelegationManager's completeQueuedWithdrawal function
 * This helps verify if the withdrawal completion would succeed before actually submitting the transaction
 *
 * @param withdrawal The withdrawal struct
 * @param tokens The tokens array to receive
 * @param receiveAsTokens Whether to receive as tokens
 * @param staker The staker address (sender of the transaction)
 * @param publicClient The Ethereum public client
 * @returns Result of the simulation (success/failure and any error message)
 */
export async function simulateCompleteWithdrawal(
  withdrawal: any,
  tokens: Address[],
  receiveAsTokens: boolean,
  staker: Address
): Promise<{ success: boolean, error?: string }> {
  try {
    // First verify the contract exists on Eth Sepolia public client
    const sepoliaPublicClient = publicClients[11155111]; // Sepolia chain ID
    const code = await sepoliaPublicClient.getCode({ address: STRATEGY_MANAGER_ADDRESS });
    if (!code) {
      throw new Error(`No contract code found at ${STRATEGY_MANAGER_ADDRESS}`);
    }
    console.log("Simulating completeQueuedWithdrawal with parameters:");
    console.log("withdrawal:", withdrawal);
    console.log("tokens:", tokens);
    console.log("receiveAsTokens:", receiveAsTokens);
    console.log("staker:", staker);

    // Simulate the call using eth_call with state override
    const result = await sepoliaPublicClient.simulateContract({
      address: DELEGATION_MANAGER_ADDRESS,
      abi: DelegationManagerABI,
      functionName: 'completeQueuedWithdrawal',
      args: [withdrawal, tokens, receiveAsTokens],
      account: staker,
    });

    console.log("Simulation successful:", result);
    return { success: true };
  } catch (error: any) {
    console.error('Error simulating completeQueuedWithdrawal:', error);
    // Extract the revert reason if available
    let errorMessage = 'Failed to simulate complete withdrawal';
    if (error.cause?.reason) {
      errorMessage = error.cause.reason;
    } else if (error.message) {
      errorMessage = error.message;
    }

    return {
      success: false,
      error: errorMessage
    };
  }
}

/**
 * Simulates a call to the DelegationManager's undelegate function
 * This helps verify if the undelegation would succeed before actually submitting the transaction
 *
 * @param staker The staker address to undelegate
 * @param sender The sender of the transaction
 * @param publicClient The Ethereum public client
 * @returns Result of the simulation (success/failure and any error message)
 */
export async function simulateUndelegate(
  staker: Address,
  sender: Address,
): Promise<{ success: boolean, error?: string }> {
  try {
    // First verify the contract exists on Eth Sepolia public client
    const sepoliaPublicClient = publicClients[11155111]; // Sepolia chain ID
    const code = await sepoliaPublicClient.getCode({ address: STRATEGY_MANAGER_ADDRESS });
    if (!code) {
      throw new Error(`No contract code found at ${STRATEGY_MANAGER_ADDRESS}`);
    }
    console.log("Simulating undelegate with parameters:");
    console.log("staker:", staker);
    console.log("sender:", sender);

    // Simulate the call using eth_call
    const result = await sepoliaPublicClient.simulateContract({
      address: DELEGATION_MANAGER_ADDRESS,
      abi: [
        {
          name: 'undelegate',
          type: 'function',
          stateMutability: 'nonpayable',
          inputs: [
            { name: 'staker', type: 'address' }
          ],
          outputs: [{ name: '', type: 'bytes32[]' }]
        }
      ],
      functionName: 'undelegate',
      args: [staker],
      account: sender
    });

    console.log("Simulation successful:", result);
    return { success: true };
  } catch (error: any) {
    console.error('Error simulating undelegate:', error);
    // Extract the revert reason if available
    let errorMessage = 'Failed to simulate undelegation';
    if (error.cause?.reason) {
      errorMessage = error.cause.reason;
    } else if (error.message) {
      errorMessage = error.message;
    }

    return {
      success: false,
      error: errorMessage
    };
  }
}

/**
 * Wrapper function that handles chain switching and callbacks for simulating operations on Eigenlayer
 * @param switchChain Function to switch chains
 * @param simulate Callback function that performs the simulation
 * @param callbacks Optional callback functions for success and error cases
 */
export async function simulateOnEigenlayer(
  callbacks: {
    simulate: () => Promise<{ success: boolean, error?: string }>,
    switchChain: (chainId: number) => Promise<void>,
    onSuccess?: () => void | Promise<void>,
    onError?: (error: string) => void | Promise<void>
  }
): Promise<void> {
  try {
    // Switch to Eth Sepolia first
    await callbacks.switchChain(EthSepolia.chainId);

    // Run the simulation
    const simulationResult = await callbacks.simulate();

    // Handle simulation result
    if (!simulationResult.success) {
      if (callbacks?.onError) {
        await callbacks.onError(simulationResult.error || 'Unknown simulation error');
      }
    } else {
      if (callbacks?.onSuccess) {
        await callbacks.onSuccess();
      }
    }
  } catch (error) {
    // Handle any unexpected errors
    if (callbacks?.onError) {
      await callbacks.onError(error instanceof Error ? error.message : 'Unexpected error during simulation');
    }
  } finally {
    // Always switch back to Base Sepolia at the end
    await callbacks.switchChain(BaseSepolia.chainId);
  }
}

/**
 * Simulates a reward claim operation on EigenLayer
 *
 * @param l1Client The L1 client to use
 * @param walletAddress The wallet address
 * @param eigenAgentAddress The EigenAgent address
 * @param rewardsCoordinatorAddress The RewardsCoordinator address
 * @param claim The rewards claim data
 * @param recipient The recipient address
 * @returns Result of the simulation
 */
export async function simulateRewardsClaim(
  l1Client: any,
  walletAddress: Address,
  eigenAgentAddress: Address,
  rewardsCoordinatorAddress: Address,
  claim: any, // RewardsMerkleClaim type
  recipient: Address
): Promise<{ success: boolean, error?: string }> {
  try {
    // Import the encoder for the message
    const { encodeProcessClaimMsg } = await import('./encoders');

    // Encode the call to processClaim
    const calldata = encodeProcessClaimMsg(claim, recipient);
    console.log("Calldata processedClaim: ", calldata);

    // Log the wallet address for debugging
    console.log("Simulating with account:", walletAddress);

    // Simulate the call through the EigenAgent with the provided wallet address
    await l1Client.simulateContract({
      address: eigenAgentAddress,
      abi: [
        {
          name: 'execute',
          type: 'function',
          inputs: [
            { name: 'to', type: 'address' },
            { name: 'value', type: 'uint256' },
            { name: 'data', type: 'bytes' },
            { name: 'operation', type: 'uint8' }
          ],
          outputs: [{ name: '', type: 'bytes' }],
          stateMutability: 'nonpayable'
        }
      ] as const,
      functionName: 'execute',
      args: [
        rewardsCoordinatorAddress,
        0n,
        calldata,
        0
      ],
      account: walletAddress
    });

    return { success: true };
  } catch (error: any) {
    console.error('Simulation failed:', error);

    // Extract the revert reason if available
    let errorMessage = 'Failed to simulate rewards claim';
    if (error.cause?.reason) {
      errorMessage = error.cause.reason;
    } else if (error.message) {
      errorMessage = error.message;
    }

    return {
      success: false,
      error: errorMessage
    };
  }
}