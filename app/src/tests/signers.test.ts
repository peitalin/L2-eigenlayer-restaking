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
  http,
} from 'viem';
import { sepolia } from 'viem/chains';
import dotenv from 'dotenv';

// Load environment variables at the beginning of the test file
dotenv.config();

// Mock the viem functions
vi.mock('viem', async (importOriginal) => {
  const actual = await importOriginal() as any;

  // Create a modified version of createWalletClient that returns a mocked client
  const mockedCreateWalletClient = (...args: any[]) => {
    const client = actual.createWalletClient(...args);

    // Replace signTypedData with a mock that returns a valid signature
    client.signTypedData = vi.fn().mockResolvedValue(
      '0x39eda06888038d13dc1bfef094fc53cc2deecb182f6a78e4a1de44c8c7cb6e8095e98095242586a357bccd6c291a52141dcd1638cb71e2bca4208ff580e94851b' as Hex
    );

    return client;
  };

  return {
    ...actual,
    createWalletClient: mockedCreateWalletClient,
  };
});

describe('EigenAgent Signature Functions', () => {
  // Test accounts and setup
  const testPrivateKey: Hex = process.env.TEST_PRIVATE_KEY as Hex;
  if (!testPrivateKey) {
    throw new Error('TEST_PRIVATE_KEY is not set');
  }

  // Setup constants and test variables
  const testOwner = privateKeyToAccount(testPrivateKey);
  let testEigenAgentAddress: Address = '0xd1c80a6ed1ff622832841aebcf8f109c6c23a9ee' as Address; // Default test address
  const testExecNonce = 1n;
  const testChainId = 11155111; // Sepolia
  const testExpiry = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 hour from now as bigint
  const testTargetAddress: Address = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';

  const walletClient = createWalletClient({
    account: testOwner,
    chain: sepolia,
    transport: http('https://sepolia.gateway.tenderly.co')
  });

  // Simplified beforeAll just for setting address
  beforeAll(() => {
    // Use a predetermined test address
    testEigenAgentAddress = '0xd1c80a6ed1ff622832841aebcf8f109c6c23a9ee' as Address;
    console.log('Using test EigenAgent address:', testEigenAgentAddress);
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
      walletClient,
      walletClient.account.address,
      testEigenAgentAddress,
      testChainId,
      testTargetAddress,
      "0x", // empty calldata
      testExecNonce,
      testExpiry
    );

    expect(signature).toBeDefined();
    expect(signature.startsWith('0x')).toBe(true);
    expect(signature.length).toBeGreaterThan(66); // minimum EIP-712 signature length
  });

  it('should generate a valid signature for an ETH transfer', async () => {
    const { signature, messageWithSignature } = await signMessageForEigenAgentExecution(
      walletClient,
      walletClient.account.address,
      testEigenAgentAddress,
      testChainId,
      testTargetAddress,
      '0x', // messageToEigenlayer
      testExecNonce,
      testExpiry
    );

    expect(signature).toBeDefined();
    expect(signature.startsWith('0x')).toBe(true);
    expect(signature.length).toBeGreaterThan(66);
  });

  it('should generate messageWithSignature that matches the target message', async () => {
    // Define the function ABI - same as in earlier test
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

    // Use a specific address (bob for solidity t) that matches the expected output
    const signerAddress = '0xa6ab3a612722d5126b160eef5b337b8a04a76dd8' as Address;

    // Use a specific expiry that matches the expected output
    const expiry = 1000650n; // 0x000f44ca in hex

    // Expected message from solidity test
    // forge test --mt test_ClientSigner_signMessageForEigenAgentExecution -vvvv
    const expectedMessage = '0x37dab62700000000000000000000000000000000000000000000000000000000000004d100000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000009736f6d657468696e670000000000000000000000000000000000000000000000000000000000000000000000a6ab3a612722d5126b160eef5b337b8a04a76dd800000000000000000000000000000000000000000000000000000000000f44ca039eda06888038d13dc1bfef094fc53cc2deecb182f6a78e4a1de44c8c7cb6e8095e98095242586a357bccd6c291a52141dcd1638cb71e2bca4208ff580e94851b';

    // Mock the wallet client to return our expected signature
    const mockClient = {
      signTypedData: vi.fn().mockResolvedValue(
        '0x39eda06888038d13dc1bfef094fc53cc2deecb182f6a78e4a1de44c8c7cb6e8095e98095242586a357bccd6c291a52141dcd1638cb71e2bca4208ff580e94851b' as Hex
      )
    };

    // Call the function with our test parameters
    const { signature, messageWithSignature } = await signMessageForEigenAgentExecution(
      mockClient as any,
      signerAddress,
      testEigenAgentAddress,
      testChainId,
      testTargetAddress,
      callData,
      0n, // execNonce
      expiry
    );

    console.log('Signature:', signature);
    expect(signature.startsWith('0x')).toBe(true);
    expect(signature.length).toBe(132);

    // Verify that the signature portion of messageWithSignature has the '0' prefix
    const signatureStart = messageWithSignature.length - (132 - 2); // -2 for '0x'
    const embeddedSignature = messageWithSignature.slice(signatureStart);
    expect(embeddedSignature).toBe('039eda06888038d13dc1bfef094fc53cc2deecb182f6a78e4a1de44c8c7cb6e8095e98095242586a357bccd6c291a52141dcd1638cb71e2bca4208ff580e94851b');

    // Log both messages for debugging
    // console.log('Generated message:', messageWithSignature);
    // console.log('\nExpected message:', expectedMessage);

    // Check if they match
    expect(messageWithSignature).toEqual(expectedMessage);
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

    // same expected hash as in the Solidity test
    const expectedHash = '0xfbd4755832659339a0fce01fe6d0da7b477ff33f806a164db9fe9a16ca891d72';
    expect(digestHash).toBe(expectedHash);
  });

});