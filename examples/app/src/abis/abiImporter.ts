import { Abi } from 'viem';

// Import ABIs from JSON files
import DelegationManagerAbiRaw from './IDelegationManager.json';
import StrategyManagerAbiRaw from './IStrategyManager.json';
import IERC20AbiRaw from './IERC20.json';
import SenderCCIPAbiRaw from './ISenderCCIP.json';
import SenderHooksAbiRaw from './ISenderHooks.json';
import EigenAgent6551AbiRaw from './IEigenAgent6551.json';
import AgentFactoryAbiRaw from './IAgentFactory.json';
import RewardsCoordinatorAbiRaw from './IRewardsCoordinator.json';
import FaucetAbiRaw from './Faucet.json';

// Export the ABIs with proper typing
export const DelegationManagerABI = DelegationManagerAbiRaw.abi as Abi;
export const StrategyManagerABI = StrategyManagerAbiRaw.abi as Abi;
export const IERC20ABI = IERC20AbiRaw.abi as Abi;
export const SenderCCIPABI = SenderCCIPAbiRaw.abi as Abi;
export const SenderHooksABI = SenderHooksAbiRaw.abi as Abi;
export const EigenAgent6551ABI = EigenAgent6551AbiRaw.abi as Abi;
export const AgentFactoryABI = AgentFactoryAbiRaw.abi as Abi;
export const RewardsCoordinatorABI = RewardsCoordinatorAbiRaw.abi as Abi;
export const FaucetABI = FaucetAbiRaw.abi as Abi;
// For backward compatibility
export const ERC20_ABI = IERC20ABI;

/**
 * Validates that an ABI contains specific function names
 * @param abi The ABI to validate
 * @param requiredFunctions Array of function names that must exist in the ABI
 * @returns boolean indicating if all required functions are present
 */
export function validateABI(abi: Abi, requiredFunctions: string[]): boolean {
  // Get all function names from the ABI
  const functionItems = abi.filter(item =>
    typeof item === 'object' &&
    item !== null &&
    'type' in item &&
    item.type === 'function' &&
    'name' in item &&
    typeof item.name === 'string'
  );

  const functionNames = functionItems.map(item => 'name' in item ? item.name : '');

  // Check if all required functions exist
  return requiredFunctions.every(name => functionNames.includes(name));
}

// Helper function to ensure the ABI has required functions
export function ensureAbiHasFunctions(abi: Abi, requiredFunctions: string[]): void {
  if (!validateABI(abi, requiredFunctions)) {
    const functionItems = abi.filter(item =>
      typeof item === 'object' &&
      item !== null &&
      'type' in item &&
      item.type === 'function' &&
      'name' in item
    );

    const availableFunctions = functionItems.map(item => 'name' in item ? item.name : '').join(', ');
    throw new Error(`ABI is missing required functions. Required: ${requiredFunctions.join(', ')}. Available: ${availableFunctions}`);
  }
}

// Check that our DelegationManagerABI has the required functions
const requiredDelegationManagerFunctions = [
  'cumulativeWithdrawalsQueued',
  'delegatedTo',
  'queueWithdrawals'
];
// This will throw an error if validation fails
ensureAbiHasFunctions(DelegationManagerABI, requiredDelegationManagerFunctions);

const requiredRewardsCoordinatorFunctions = [
  'getCurrentDistributionRoot',
  'getDistributionRootsLength',
  'processClaims'
];
ensureAbiHasFunctions(RewardsCoordinatorABI, requiredRewardsCoordinatorFunctions);

// Define required functions for other ABIs
const requiredStrategyManagerFunctions = [
  'depositIntoStrategy',
  'getDeposits',
  'stakerDepositShares'
];
ensureAbiHasFunctions(StrategyManagerABI, requiredStrategyManagerFunctions);

// Required functions for IERC20
const requiredIERC20Functions = [
  'balanceOf',
  'allowance',
  'approve',
  'transfer',
  'transferFrom'
];
ensureAbiHasFunctions(IERC20ABI, requiredIERC20Functions);

const requiredSenderHooksFunctions = [
  'getGasLimitForFunctionSelector'
];
ensureAbiHasFunctions(SenderHooksABI, requiredSenderHooksFunctions);

const requiredSenderCCIPFunctions = [
  'sendMessagePayNative'
];
ensureAbiHasFunctions(SenderCCIPABI, requiredSenderCCIPFunctions);


