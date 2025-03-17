// Import ABIs from abiUtils.ts
import {
  DelegationManagerABI,
  StrategyManagerABI,
  IERC20ABI,
  SenderCCIPABI,
  EigenAgent6551ABI,
  AgentFactoryABI
} from './abiUtils';

// Export the ABIs
export {
  DelegationManagerABI,
  StrategyManagerABI,
  IERC20ABI,
  SenderCCIPABI,
  EigenAgent6551ABI,
  AgentFactoryABI
};

// Keep backward compatibility with existing code
export const agentFactoryAbi = AgentFactoryABI;
export const eigenAgentAbi = EigenAgent6551ABI;
export const senderCCIPAbi = SenderCCIPABI;
export const strategyManagerAbi = StrategyManagerABI;
export const ERC20_ABI = IERC20ABI;

// Export chainlink ABIs
export * from './Router';

/**
 * Re-export validation functions from abiUtils
 */
export {
  validateABI,
  ensureAbiHasFunctions
} from './abiUtils';