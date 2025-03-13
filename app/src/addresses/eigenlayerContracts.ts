import { Address } from 'viem';
import ethSepoliaConfig from './ethsepolia/eigenlayerContracts.config.json';

export const STRATEGY_MANAGER_ADDRESS = ethSepoliaConfig.addresses.StrategyManager as Address;
export const DELEGATION_MANAGER_ADDRESS = ethSepoliaConfig.addresses.DelegationManager as Address;
export const ALLOCATION_MANAGER_ADDRESS = ethSepoliaConfig.addresses.AllocationManager as Address;
export const REWARDS_COORDINATOR_ADDRESS = ethSepoliaConfig.addresses.RewardsCoordinator as Address;

export const ERC20_TOKEN_ADDRESS = ethSepoliaConfig.addresses.TokenERC20 as Address;
export const STRATEGY = ethSepoliaConfig.addresses.strategies.CCIPStrategy as Address;
