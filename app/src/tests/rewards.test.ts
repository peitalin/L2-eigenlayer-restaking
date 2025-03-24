import { describe, it, expect } from 'vitest';
import { Address } from 'viem';
import { calculateTokenLeafHash, calculateEarnerLeafHash, createClaim, createEarnerTreeOneToken } from '../utils/rewards';
import { EthSepolia } from '../addresses';
import { encodeProcessClaimMsg } from '../utils/encoders';
import { RewardsMerkleClaim } from '../abis/RewardsCoordinatorTypes';

describe('Rewards Hash Functions', () => {
  it('should calculate token leaf hash correctly', () => {
    const amount = 100000000000000000n;
    const expectedHash = "0x2275559c723ed63f581166bd0fd7ae1e8cbda26ea166d9614e5dbc1061a553aa";

    // Create token leaf
    const tokenLeaf = {
      token: EthSepolia.bridgeToken,
      cumulativeEarnings: amount
    };

    // Calculate token leaf hash
    const tokenLeafHash = calculateTokenLeafHash(tokenLeaf);

    // Verify the hash matches expected value
    expect(tokenLeafHash.toLowerCase()).toBe(expectedHash.toLowerCase());
  });

  it('should calculate earner leaf hash correctly using the token leaf hash', () => {
    const amount = 100000000000000000n;
    const testAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8' as Address;

    // First create and calculate the token leaf hash
    const tokenLeaf = {
      token: EthSepolia.bridgeToken,
      cumulativeEarnings: amount
    };

    const tokenLeafHash = calculateTokenLeafHash(tokenLeaf);

    // Create the earner leaf using the token leaf hash
    const earnerLeaf = {
      earner: testAddress,
      earnerTokenRoot: tokenLeafHash
    };

    // Calculate the earner leaf hash
    const earnerLeafHash = calculateEarnerLeafHash(earnerLeaf);

    // Verify it produces a valid hash (can't check against a known value)
    expect(earnerLeafHash).toBeDefined();
    expect(earnerLeafHash.startsWith('0x')).toBe(true);
    expect(earnerLeafHash.length).toBe(66); // 32 bytes + 0x prefix

    // Changing any input should produce a different hash
    const differentAddressLeaf = {
      earner: '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC' as Address,
      earnerTokenRoot: tokenLeafHash
    };

    const differentHash = calculateEarnerLeafHash(differentAddressLeaf);
    expect(differentHash).not.toBe(earnerLeafHash);
  });

  it('should correctly encode processClaim message', () => {
    // Define expected hex message
    const expectedMessage = "0x3ccc861d0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000abac0ee51946b38a02ad8150fa85e9147bc8851f000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000abac0ee51946b38a02ad8150fa85e9147bc8851f2275559c723ed63f581166bd0fd7ae1e8cbda26ea166d9614e5dbc1061a553aa0000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000af03f2a302a2c4867d622de44b213b8f870c0f1a000000000000000000000000000000000000000000000000016345785d8a0000";

    // Recipient is the EigenAgent address
    const recipient: Address = '0xabac0ee51946b38a02ad8150fa85e9147bc8851f';
    const bridgeToken: Address = EthSepolia.bridgeToken;

    // Create the claim object similar to what's done in RewardsComponent.tsx
    const claim: RewardsMerkleClaim = createClaim(
      1, // rootIndex
      recipient, // earner
      100000000000000000n, // amount: 0.1 ether
      '0x', // proof is empty as there's only 1 claim
      0 // earnerIndex
    );

    // Encode the message for processing the claim
    const message = encodeProcessClaimMsg(claim, recipient);

    // Verify message matches expected output (case insensitive comparison)
    expect(message.toLowerCase()).toBe(expectedMessage.toLowerCase());

    // Also verify the message contains the correct recipient address
    expect(message.toLowerCase()).toContain(recipient.toLowerCase().substring(2)); // without 0x prefix

    // Verify the message contains the token address (bridge token)
    expect(message.toLowerCase()).toContain(bridgeToken.toLowerCase().substring(2)); // without 0x prefix

    // Verify the message contains the function selector for processClaim
    expect(message.startsWith('0x3ccc861d')).toBe(true);
  });
});

describe('Rewards Merkle Tree Tests', () => {
  it('should create correct RewardsMerkle tree for one token with expected root', () => {
    // Setup test parameters
    const earners: [Address, Address, Address, Address] = [
      '0x1111111111111111111111111111111111111111',
      '0x2222222222222222222222222222222222222222',
      '0x3333333333333333333333333333333333333333',
      '0x4444444444444444444444444444444444444444'
    ];

    const tokenAddress = EthSepolia.bridgeToken as Address;

    // Using exact values that will generate the expected root
    const rewardAmounts: [bigint, bigint, bigint, bigint] = [
      100000000000000000n, // 0.1 ETH
      200000000000000000n, // 0.2 ETH
      300000000000000000n, // 0.3 ETH
      400000000000000000n  // 0.4 ETH
    ];

    // Create the Merkle tree
    const tree = createEarnerTreeOneToken(
      earners,
      tokenAddress,
      rewardAmounts
    );

    // Assert that the root matches the expected value (from solidity test)
    expect(tree.root).toBe('0x3e37fe74c0db1b3246a76c3d7ef75b725bef138ea50230bf8486ba1d5693882d');
  });
});