import { Address } from 'viem';
import ethSepoliaConfig from './ethsepolia/bridgeContractsL1.config.json';

export const RECEIVER_CCIP_ADDRESS = ethSepoliaConfig.contracts.receiverCCIP as Address;
export const RESTAKING_CONNECTOR_ADDRESS = ethSepoliaConfig.contracts.restakingConnector as Address;
export const REGISTRY_6551_ADDRESS = ethSepoliaConfig.contracts.registry6551 as Address;
export const BASE_EIGEN_AGENT_ADDRESS = ethSepoliaConfig.contracts.baseEigenAgent as Address;
export const EIGEN_AGENT_OWNER_721_ADDRESS = ethSepoliaConfig.contracts.eigenAgentOwner721 as Address;
export const AGENT_FACTORY_ADDRESS = ethSepoliaConfig.contracts.agentFactory as Address;