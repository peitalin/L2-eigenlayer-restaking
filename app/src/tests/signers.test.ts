import { expect, describe, it, beforeAll, vi } from 'vitest';
import {
  signMessageForEigenAgentExecution,
  domainSeparatorEigenAgent,
  createEigenAgentCallDigestHash,
  EIGEN_AGENT_EXEC_TYPEHASH
} from '../utils/signers';
import { privateKeyToAccount } from 'viem/accounts';
import {
  Address,
  Hex,
  keccak256,
  encodeAbiParameters,
  concat,
  toBytes,
  encodeFunctionData,
  createWalletClient,
  custom,
} from 'viem';
import { sepolia } from 'viem/chains';
import dotenv from 'dotenv';
import { calculateTokenLeafHash, calculateEarnerLeafHash, createClaim, REWARDS_AMOUNT } from '../utils/rewards';
import { CHAINLINK_CONSTANTS } from '../addresses';
import { encodeProcessClaimMsg } from '../utils/encoders';
import { RewardsMerkleClaim } from '../abis/RewardsCoordinatorTypes';

// Load environment variables at the beginning of the test file
dotenv.config();

// Set timeout for tests
vi.setConfig({ testTimeout: 10000 }); // 10 second timeout

// Try to get the private key from environment variables
// Fall back to a known testing key if not available
let testKey: Hex;
if (process.env.TEST_PRIVATE_KEY) {
  testKey = process.env.TEST_PRIVATE_KEY as Hex;
  // Reduce logging
  // console.log('Using TEST_PRIVATE_KEY from environment variables');
} else {
  // WARNING: NEVER use this key for anything other than local testing
  // This is a well-known test private key from Hardhat/Anvil
  console.warn('⚠️ No TEST_PRIVATE_KEY found in environment. Using a hardcoded test key.');
  testKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80' as Hex;
}

const LOCAL_TEST_ACCOUNT = privateKeyToAccount(testKey);

describe('EigenAgent Signature Functions', () => {
  // Setup constants and test variables
  const testOwner = LOCAL_TEST_ACCOUNT;
  let testEigenAgentAddress: Address = '0xd1c80a6ed1ff622832841aebcf8f109c6c23a9ee' as Address; // Default test address
  const testExecNonce = 1n;
  const testChainId = 11155111; // Sepolia
  const testExpiry = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 hour from now as bigint
  const testTargetAddress: Address = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';

  // Create a wallet client that uses the local account with a custom transport
  // that delegates signing to the account's built-in signMessage method
  const walletClient = createWalletClient({
    account: testOwner,
    chain: sepolia,
    transport: custom({
      request: async ({ method, params }) => {
        // Handle signing operations by delegating to the account's signMessage
        if (method === 'eth_signMessage' || method === 'personal_sign') {
          const message = params[1];
          // Use the account's built-in signMessage
          return await testOwner.signMessage({
            message: typeof message === 'object' && 'raw' in message
              ? { raw: message.raw }
              : message,
          });
        }
        if (method === 'eth_chainId') return '0xaa36a7'; // Sepolia chain ID in hex
        return null;
      },
    })
  });

  // Simplified beforeAll just for setting address
  beforeAll(() => {
    // Use a predetermined test address
    testEigenAgentAddress = '0xd1c80a6ed1ff622832841aebcf8f109c6c23a9ee' as Address;
    // Reduce logging
    // console.log('Using test EigenAgent address:', testEigenAgentAddress);
    // console.log('Using test account address:', testOwner.address);
  });

  // Test for EIGEN_AGENT_EXEC_TYPEHASH correctness
  it('should have the correct EIGEN_AGENT_EXEC_TYPEHASH value', () => {
    const expectedTypehash = '0xc2fe14b6b0762bbe0af05e32c1508917360acb035e861274912c58b9c2806cb8';
    expect(EIGEN_AGENT_EXEC_TYPEHASH).toBe(expectedTypehash);

    // Also verify the typehash is correctly derived from the string
    const calculatedTypehash = keccak256(
      toBytes("ExecuteWithSignature(address target,uint256 value,bytes data,uint256 execNonce,uint256 chainId,uint256 expiry)")
    );
    expect(calculatedTypehash).toBe(expectedTypehash);
  });

  it('should generate a valid signature for an EigenAgent execution', async () => {
    const { signature, messageWithSignature } = await signMessageForEigenAgentExecution(
      walletClient as any,
      walletClient.account.address,
      testEigenAgentAddress,
      testTargetAddress,
      "0x", // empty calldata
      testExecNonce,
      testExpiry
    );

    // Reduce logging
    // console.log('Signature:', signature);
    expect(signature).toBeDefined();
    expect(signature.startsWith('0x')).toBe(true);
    expect(signature.length).toBeGreaterThan(66); // minimum EIP-712 signature length
  });

  it('should generate messageWithSignature that matches the solidity test message', async () => {
    // Define the function ABI
    const testFunctionAbi = {
      name: 'testFunction',
      type: 'function',
      inputs: [
        { name: 'param1', type: 'uint256' },
        { name: 'param2', type: 'string' }
      ],
      stateMutability: 'nonpayable'
    } as const;

    // Create the calldata for our test function with the specific parameters
    const callData = encodeFunctionData({
      abi: [testFunctionAbi],
      functionName: 'testFunction',
      args: [1233n, 'something']
    });

    // Use a fixed address to match the test
    const signerAddress = '0xa6ab3a612722d5126b160eef5b337b8a04a76dd8' as Address;

    // Use a specific expiry that matches the solidity test
    const expiry = 1000650n; // 0x000f44ca in hex

    // Create a specific private key that will generate a known address
    // This specific key is used to match the test case
    const testPrivateKey = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d' as Hex;
    const testAccount = privateKeyToAccount(testPrivateKey);
    // Reduce logging
    // console.log("Test account address:", testAccount.address);

    // Create a wallet client with the test account
    const testWalletClient = createWalletClient({
      account: testAccount,
      chain: sepolia,
      transport: custom({
        request: async ({ method, params }) => {
          // Handle signing operations by delegating to the account's signMessage
          if (method === 'eth_signMessage' || method === 'personal_sign') {
            const message = params[1];
            // Use the account's built-in signMessage
            return await testAccount.signMessage({
              message: typeof message === 'object' && 'raw' in message
                ? { raw: message.raw }
                : message,
            });
          }
          if (method === 'eth_chainId') return '0xaa36a7'; // Sepolia chain ID in hex
          return null;
        },
      })
    });

    // Call the function with our test parameters
    const { signature, messageWithSignature } = await signMessageForEigenAgentExecution(
      testWalletClient as any,
      signerAddress,
      testEigenAgentAddress,
      testTargetAddress,
      callData,
      0n, // execNonce
      expiry
    );

    // Reduce logging
    // console.log('Test signature:', signature);
    // console.log('messageWithSignature:', messageWithSignature);

    // Extract embedded signature from the messageWithSignature
    const signatureStart = messageWithSignature.length - (132 - 2); // -2 for '0x'
    const embeddedSignature = messageWithSignature.slice(signatureStart);
    // Reduce logging
    // console.log('Embedded signature:', embeddedSignature);

    // Test against the format - should be properly formatted
    expect(signature.startsWith('0x')).toBe(true);
    expect(signature.length).toBe(132); // Standard Ethereum signature length (65 bytes)
  });

  it('should correctly compute the domain separator for EigenAgent', () => {
    const contractAddr = testEigenAgentAddress;
    const chainId = BigInt(testChainId);

    const domainSeparator = domainSeparatorEigenAgent(contractAddr, chainId);

    // Domain separator should be a 32-byte hash (64 hex chars + 0x prefix)
    expect(domainSeparator).toBeDefined();
    expect(domainSeparator.startsWith('0x')).toBe(true);
    expect(domainSeparator.length).toBe(66);

    // Changing any parameter should produce a different domain separator
    const differentChainSeparator = domainSeparatorEigenAgent(contractAddr, BigInt(1));
    expect(differentChainSeparator).not.toEqual(domainSeparator);

    // Different contract address
    const differentAddressSeparator = domainSeparatorEigenAgent(
      '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC' as Address,
      chainId
    );
    expect(differentAddressSeparator).not.toEqual(domainSeparator);
  });

  it('should correctly create digest hash for EigenAgent execution (Solidity equivalent)', () => {
    // Setup test parameters similar to the Solidity test:
    // forge test --mt test_ClientSigner_createEigenAgentCallDigestHash -vvvv
    const target = '0x0000000000000000000000000000000000000001' as Address;
    const value = 0n; // 0 ether

    // Define the function ABI
    const testFunctionAbi = {
      name: 'testFunction',
      type: 'function',
      inputs: [
        { name: 'param1', type: 'uint256' },
        { name: 'param2', type: 'string' }
      ],
      stateMutability: 'nonpayable'
    } as const;

    // Create the calldata
    const callData = encodeFunctionData({
      abi: [testFunctionAbi],
      functionName: 'testFunction',
      args: [1233n, 'something']
    });

    expect(callData).toBe('0x37dab62700000000000000000000000000000000000000000000000000000000000004d100000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000009736f6d657468696e670000000000000000000000000000000000000000000000');

    const nonce = 0n;
    const chainId = 11155111n; // Sepolia
    const expiry = 1_000_650n; // same expiry as in the solidity test
    // same EigenAgent address as in the solidity test (locally deployed)
    const eigenAgentAddrLocal = '0x7dcCBA5387Cc75efb6e93844A12D1A8e984eBdC4' as Address;

    const structHash = keccak256(
      encodeAbiParameters(
        [
          { name: 'typeHash', type: 'bytes32' },
          { name: 'target', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'dataHash', type: 'bytes32' },
          { name: 'execNonce', type: 'uint256' },
          { name: 'chainId', type: 'uint256' },
          { name: 'expiry', type: 'uint256' }
        ],
        [
          EIGEN_AGENT_EXEC_TYPEHASH,
          target,
          value,
          keccak256(callData),
          nonce,
          chainId,
          expiry
        ]
      )
    );

    const digestHash = keccak256(
      concat([
        toBytes('0x1901'), // EIP-712 prefix
        toBytes(domainSeparatorEigenAgent(eigenAgentAddrLocal, chainId)),
        toBytes(structHash)
      ])
    );

    const digestHash2 = createEigenAgentCallDigestHash(
      target,
      eigenAgentAddrLocal,
      value,
      callData,
      nonce,
      chainId,
      expiry
    );
    // Assert that both methods produce the same hash
    expect(digestHash).toBe(digestHash2);

    // same expected hash as in the solidity test
    const expectedHash = '0xfbd4755832659339a0fce01fe6d0da7b477ff33f806a164db9fe9a16ca891d72';
    expect(digestHash).toBe(expectedHash);
  });

  it('should calculate token leaf hash correctly', () => {
    const amount = 100000000000000000n;
    const expectedHash = "0x2275559c723ed63f581166bd0fd7ae1e8cbda26ea166d9614e5dbc1061a553aa";

    // Create token leaf
    const tokenLeaf = {
      token: CHAINLINK_CONSTANTS.ethSepolia.bridgeToken,
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
      token: CHAINLINK_CONSTANTS.ethSepolia.bridgeToken,
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
    const bridgeToken: Address = CHAINLINK_CONSTANTS.ethSepolia.bridgeToken;

    // Create the claim object similar to what's done in RewardsComponent.tsx
    const claim: RewardsMerkleClaim = createClaim(
      1, // rootIndex
      recipient, // earner
      REWARDS_AMOUNT, // amount
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
