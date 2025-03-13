import { Address } from 'viem';

// Chain constants from script/Addresses.sol
export const CHAINLINK_CONSTANTS = {
  ethSepolia: {
    router: '0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59' as Address,
    chainSelector: '16015286601757825753',
    tokenBnM: '0xAf03f2a302A2C4867d622dE44b213b8F870c0f1a' as Address,
    bridgeToken: '0xAf03f2a302A2C4867d622dE44b213b8F870c0f1a' as Address,
    link: '0x779877A7B0D9E8603169DdbD7836e478b4624789' as Address,
    chainId: 11155111n,
    poolAddress: '0x886330448089754e998BcEfa2a56a91aD240aB60' as Address
  },
  baseSepolia: {
    router: '0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93' as Address,
    chainSelector: '10344971235874465080',
    tokenBnM: '0x886330448089754e998BcEfa2a56a91aD240aB60' as Address,
    bridgeToken: '0x886330448089754e998BcEfa2a56a91aD240aB60' as Address,
    link: '0xE4aB69C077896252FAFBD49EFD26B5D171A32410' as Address,
    chainId: 84532n,
    poolAddress: '0x369a189bE07f42DE9767fBb6d0327eedC129CC15' as Address
  }
};

// Direct exports for the most commonly used addresses
export const ETH_SEPOLIA_ROUTER = CHAINLINK_CONSTANTS.ethSepolia.router;
export const BASE_SEPOLIA_ROUTER = CHAINLINK_CONSTANTS.baseSepolia.router;

// Export all address constants from a single file
export * from './eigenlayerContracts';
export * from './baseSepoliaContracts';

// Re-export any other address-related constants here
