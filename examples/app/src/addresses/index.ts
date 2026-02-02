import { Address } from 'viem';

export interface ChainlinkConfig {
  router: Address;
  chainSelector: string;
  bridgeToken: Address;
  link: Address;
  chainId: number;
  poolAddress: Address;
  // extra frontend fields
  name: string;
  rpcUrl: string;
  explorerUrl: string;
}

// Chainlink constants from script/Addresses.sol
export const EthSepolia: ChainlinkConfig = {
  router: '0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59' as Address,
  chainSelector: '16015286601757825753',
  bridgeToken: '0xAf03f2a302A2C4867d622dE44b213b8F870c0f1a' as Address,
  link: '0x779877A7B0D9E8603169DdbD7836e478b4624789' as Address,
  chainId: 11155111,
  poolAddress: '0xa0f5588fa098b56f28a8ae65caaa43fefcaf608c' as Address,
  // extra frontend fields
  name: 'Ethereum Sepolia',
  rpcUrl: import.meta.env?.VITE_ETHSEPOLIA_RPC_URL || 'https://sepolia.infura.io/v3/',
  explorerUrl: 'https://sepolia.etherscan.io',
};

export const FaucetL2 = '0xf99Ae69F60edBFf5a6D5E0627D997fc9585Ff937' as Address;

export const BaseSepolia: ChainlinkConfig = {
  router: '0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93' as Address,
  chainSelector: '10344971235874465080',
  bridgeToken: '0x886330448089754e998BcEfa2a56a91aD240aB60' as Address,
  link: '0xE4aB69C077896252FAFBD49EFD26B5D171A32410' as Address,
  chainId: 84532,
  poolAddress: '0x369a189bE07f42DE9767fBb6d0327eedC129CC15' as Address,
  // extra frontend fields
  name: 'Base Sepolia',
  rpcUrl: import.meta.env?.VITE_BASESEPOLIA_RPC_URL || 'https://sepolia.base.org',
  explorerUrl: 'https://sepolia.basescan.org',
};

export const TreasureTopaz: ChainlinkConfig = {
  router: '' as Address,
  chainSelector: '',
  bridgeToken: '' as Address,
  link: '' as Address,
  chainId: 978658,
  poolAddress: '0x369a189bE07f42DE9767fBb6d0327eedC129CC15' as Address,
  // extra frontend fields
  name: 'Treasure Topaz',
  rpcUrl: 'https://rpc.topaz.treasure.lol',
  explorerUrl: 'https://topaz.treasurescan.io/',
};

import bridgeContractsL2 from './basesepolia/bridgeContractsL2.config.json';
export const SENDER_CCIP_ADDRESS = bridgeContractsL2.contracts.senderCCIP as Address;
export const SENDER_HOOKS_ADDRESS = bridgeContractsL2.contracts.senderHooks as Address;

import eigenlayerContracts from './ethsepolia/eigenlayerContracts.config.json';
export const STRATEGY_MANAGER_ADDRESS = eigenlayerContracts.addresses.StrategyManager as Address;
export const DELEGATION_MANAGER_ADDRESS = eigenlayerContracts.addresses.DelegationManager as Address;
export const ALLOCATION_MANAGER_ADDRESS = eigenlayerContracts.addresses.AllocationManager as Address;
export const REWARDS_COORDINATOR_ADDRESS = eigenlayerContracts.addresses.RewardsCoordinator as Address;
export const ERC20_TOKEN_ADDRESS = eigenlayerContracts.addresses.TokenERC20 as Address;
export const STRATEGY = eigenlayerContracts.addresses.strategies.CCIPStrategy as Address;

import bridgeContractsL1 from './ethsepolia/bridgeContractsL1.config.json';
export const RECEIVER_CCIP_ADDRESS = bridgeContractsL1.contracts.receiverCCIP as Address;
export const RESTAKING_CONNECTOR_ADDRESS = bridgeContractsL1.contracts.restakingConnector as Address;
export const REGISTRY_6551_ADDRESS = bridgeContractsL1.contracts.registry6551 as Address;
export const BASE_EIGEN_AGENT_ADDRESS = bridgeContractsL1.contracts.baseEigenAgent as Address;
export const EIGEN_AGENT_OWNER_721_ADDRESS = bridgeContractsL1.contracts.eigenAgentOwner721 as Address;
export const AGENT_FACTORY_ADDRESS = bridgeContractsL1.contracts.agentFactory as Address;

