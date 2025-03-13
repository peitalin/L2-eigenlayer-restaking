import { Address } from 'viem';
import baseSepoliaConfig from './basesepolia/bridgeContractsL2.config.json';

export const SENDER_CCIP_ADDRESS = baseSepoliaConfig.contracts.senderCCIP as Address;
