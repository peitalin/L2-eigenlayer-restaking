import { describe, it, expect } from 'vitest';
import { signDelegationApproval } from './signDelegationApproval';
import { privateKeyToAccount } from 'viem/accounts';
import { config } from 'dotenv';

// Load environment variables
config();

describe('signDelegationApproval', () => {
  it('should sign a delegation approval', async () => {
    const staker = '0xAbAc0Ee51946B38a02AD8150fa85E9147bC8851F';
    const operator = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    const operatorPrivateKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'; // Default Anvil key
    const expiry = 1700600500n;

    const result = await signDelegationApproval(staker, operator, operatorPrivateKey, expiry);

    expect(result).toHaveProperty('signature');
    expect(result).toHaveProperty('expiry');
    expect(typeof result.signature).toBe('string');
    expect(result.signature.startsWith('0x')).toBe(true);
  });

  it('should generate valid delegation approval signature with specific parameters', async () => {

     // Use Anvil public default key:
     const operatorKey = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
     const operatorAccount = privateKeyToAccount(operatorKey);
     const operator = operatorAccount.address;

     // Test parameters matching the Solidity script
     const eigenAgentStaker = '0xAbAc0Ee51946B38a02AD8150fa85E9147bC8851F';
     // pre-generated digestHash using specific params in solidity version:
     const testSalt = '0x0000000000000000000000000000000000000000000000000000000000000000' as const;
     const expiry = BigInt(1700600500);

     // Call the function
     const result = await signDelegationApproval(eigenAgentStaker, operator, operatorKey, expiry, testSalt);

     // Verify the results match expected values
     expect(result.chainId).toBe('11155111'); // Sepolia chain ID
     expect(operator).toBe('0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266');
     // pre-generated digestHash and signature using Anvil default keys as Operator:
     expect(result.digestHash).toBe('0x4d695433cb6e7c620e8b27e26f611e012c266748fc6b06b1cae7a59a831f4f87');
     expect(result.signature).toBe('0x171a7c7a5248f3eb7f41cb6c91a5b5c6d0a44a5bd7a34fe1dce7b870f7756f5d662e63ea012ababfc9130bbf41baf44770614cd6d9a9be1b2d233ed12023def21c');
   });

  it('should generate valid delegation approval signature', async () => {
    // Ensure OPERATOR_KEY1 is available and properly formatted
    const operatorKeyRaw = process.env.OPERATOR_KEY1;
    if (!operatorKeyRaw) {
      throw new Error('OPERATOR_KEY1 environment variable is required for tests');
    }
    // Ensure the key starts with 0x
    const operatorKey = operatorKeyRaw.startsWith('0x') ? operatorKeyRaw as `0x${string}` : `0x${operatorKeyRaw}` as `0x${string}`;

    // Get operator address from key
    const operatorAccount = privateKeyToAccount(operatorKey);
    const operator = operatorAccount.address;

    // Test parameters
    const eigenAgentStaker = '0x1234567890123456789012345678901234567890';
    const expiry = BigInt(1700600500);

    // Call the function
    const result = await signDelegationApproval(eigenAgentStaker, operator, operatorKey, expiry);

    // Verify the structure and types of the returned data
    expect(result).toHaveProperty('signature');
    expect(result).toHaveProperty('digestHash');
    expect(result).toHaveProperty('salt');
    expect(result).toHaveProperty('expiry');
    expect(result).toHaveProperty('delegationManagerAddress');
    expect(result).toHaveProperty('chainId');

    // Verify the data types
    expect(typeof result.signature).toBe('string');
    expect(typeof result.digestHash).toBe('string');
    expect(typeof result.salt).toBe('string');
    expect(typeof result.expiry).toBe('string');
    expect(typeof result.delegationManagerAddress).toBe('string');
    expect(typeof result.chainId).toBe('string');

    // Verify the formats
    expect(result.signature).toMatch(/^0x[a-fA-F0-9]{130}$/);
    expect(result.digestHash).toMatch(/^0x[a-fA-F0-9]{64}$/);
    expect(result.salt).toMatch(/^0x[a-fA-F0-9]{64}$/);
    expect(result.chainId).toBe('11155111'); // Sepolia chain ID
  });
});