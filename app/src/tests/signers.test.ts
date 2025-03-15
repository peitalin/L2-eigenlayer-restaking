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
    console.log('Generated message:', messageWithSignature);
    console.log('\nExpected message:', expectedMessage);

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


        // senderContract.sendMessagePayNative{value: routerFees}(
        //     EthSepolia.ChainSelector, // destination chain
        //     address(receiverContract),
        //     string(messageWithSignature), // must be string
        //     tokenAmounts,
        //     gasLimit
        // );

//// Proper encoding
// 7132732a
// 000000000000000000000000000000000000000000000000de41ba4fc9d91ad9 [36] chain selector
// 0000000000000000000000000c3acbfda67bb7a8e987a77ff505730230d7ce9a [68] receiver
// 00000000000000000000000000000000000000000000000000000000000000a0 [100] message offset 160
// 00000000000000000000000000000000000000000000000000000000000001c0 [132] tokenAmounts offset 228
// 000000000000000000000000000000000000000000000000000000000008b290 [164] gasLimit
// 00000000000000000000000000000000000000000000000000000000000000e5 [200] message length
// e7a050aa
// 0000000000000000000000008353e5340689fc93b24677007f386a4d91ab5616 [236]
// 000000000000000000000000af03f2a302a2c4867d622de44b213b8f870c0f1a [268]
// 000000000000000000000000000000000000000000000000013eadacbc5a4000 [300]
// 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [332]
// 0000000000000000000000000000000000000000000000000000000067d3f7bc [364]
// 0c1d79420ee9adb307eb38c5d46cd990933bc5ab2324138d5b5a924bbbab6d15 [396]
// 38779b6162806961df9967d27b8c3118caf0bf5892763e07eb70eb8a0bd83da1 [428]
// 1c000000000000000000000000000000000000000000000000000000
// 0000000000000000000000000000000000000000000000000000000000000001
// 000000000000000000000000886330448089754e998bcefa2a56a91ad240ab60
// 000000000000000000000000000000000000000000000000013eadacbc5a4000

// 0000000000000000000000000000000000000000000000000000000000000020
// 00000000000000000000000000000000000000000000000000000000000000e5
// e7a050aa
// 0000000000000000000000008353e5340689fc93b24677007f386a4d91ab5616
// 000000000000000000000000886330448089754e998bcefa2a56a91ad240ab60
// 0000000000000000000000000000000000000000000000000186cc6acd4b0000
// 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c
// 0000000000000000000000000000000000000000000000000000000067d40f3e
// d1271d2eb9c4ccdde2173b84bb86e2e1dfd9d56a943c0749b6b8c3390206d0fa
// 51f29975ae0abf98d695a61518dbb87fd0b0524ed6a9dc57c8a26a4e545b1466
// 1b000000000000000000000000000000000000000000000000000000

// 0000000000000000000000000000000000000000000000000000000000000020
// 00000000000000000000000000000000000000000000000000000000000000e5
// e7a050aa
// 0000000000000000000000008353e5340689fc93b24677007f386a4d91ab5616
// 000000000000000000000000af03f2a302a2c4867d622de44b213b8f870c0f1a
// 000000000000000000000000000000000000000000000000013eadacbc5a4000
// 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c
// 0000000000000000000000000000000000000000000000000000000067d405ec
// 0875fbe5cb9683e89c4ac7ec004b99ff7f3ed85db22589581fbd8258aa7ed889
// 216d9c6ccbc522cfb000af99d520adf14e57288616be83e59258f3d1abc7877e
// 1c000000000000000000000000000000000000000000000000000000


/////// custom functoin selector with client.sendTransaction
// 7132732a
// 000000000000000000000000000000000000000000000000de41ba4fc9d91ad9
// 0000000000000000000000000c3acbfda67bb7a8e987a77ff505730230d7ce9a
// 00000000000000000000000000000000000000000000000000000000000000a0
// 00000000000000000000000000000000000000000000000000000000000001c0
// 0000000000000000000000000000000000000000000000000000000000000000
// 00000000000000000000000000000000000000000000000000000000000000e5
// e7a050aa
// 0000000000000000000000008353e5340689fc93b24677007f386a4d91ab5616
// 000000000000000000000000886330448089754e998bcefa2a56a91ad240ab60
// 0000000000000000000000000000000000000000000000000186cc6acd4b0000
// 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c
// 0000000000000000000000000000000000000000000000000000000067d40902
// 44eff92b92fe6744e40e57c84e00f04b100773f18f0d3ba9f94abc942af0c079
// 6d5cc6e00a421ef9ff33e74289a79c483ad8c6e21c7dd58b050b7f8f53a47796
// 1c000000000000000000000000000000000000000000000000000000
// 0000000000000000000000000000000000000000000000000000000000000001
// 000000000000000000000000886330448089754e998bcefa2a56a91ad240ab60
// 0000000000000000000000000000000000000000000000000186cc6acd4b0000
