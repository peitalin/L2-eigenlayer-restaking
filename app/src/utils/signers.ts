import { Address, Hex, Hash, concat, encodeAbiParameters, keccak256, pad, toBytes, WalletClient, createPublicClient, http, PublicClient, verifyMessage, SignableMessage, verifyTypedData, stringToHex, hexToBytes, bytesToHex, hexToString } from 'viem';
import { sepolia } from 'viem/chains';

// Constants from ClientSigners.sol
export const EIGEN_AGENT_EXEC_TYPEHASH = keccak256(
  toBytes("ExecuteWithSignature(address target,uint256 value,bytes data,uint256 execNonce,uint256 chainId,uint256 expiry)")
);
export const EIP712_DOMAIN_TYPEHASH = keccak256(
  toBytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
);
export const TREASURE_RESTAKING_VERSION = "v1.0.0";

/**
 * Creates a domain separator for EigenAgent contract
 * @param contractAddr EigenAgent contract address
 * @param chainId Chain ID where the EigenAgent is deployed
 * @returns Domain separator hash
 */
export function domainSeparatorEigenAgent(contractAddr: Address, chainId: bigint): Hash {
  // Get the major version (v1) from v1.0.0
  const majorVersion = TREASURE_RESTAKING_VERSION.substring(0, 2);
  // Directly calculate domain separator using the same approach as Solidity
  const domainSeparator = keccak256(
    encodeAbiParameters(
      [
        { name: 'typeHash', type: 'bytes32' },
        { name: 'name', type: 'bytes32' },
        { name: 'version', type: 'bytes32' },
        { name: 'chainId', type: 'uint256' },
        { name: 'verifyingContract', type: 'address' }
      ],
      [
        EIP712_DOMAIN_TYPEHASH,
        keccak256(toBytes('EigenAgent')),
        keccak256(toBytes(majorVersion)),
        chainId,
        contractAddr
      ]
    )
  );
  return domainSeparator;
}

/**
 * Implementation of createEigenAgentCallDigestHash for testing and verification
 * This function replicates the Solidity createEigenAgentCallDigestHash function
 * from ClientSigners.sol
 *
 * @param targetContractAddr Target contract to call
 * @param eigenAgentAddr EigenAgent contract address
 * @param value Amount of ETH to send
 * @param data Call data to send
 * @param execNonce Execution nonce
 * @param chainId Chain ID where the EigenAgent is deployed
 * @param expiry Timestamp when the signature expires
 * @returns Digest hash for EIP-712 signing
 */
export function createEigenAgentCallDigestHash(
  targetContractAddr: Address,
  eigenAgentAddr: Address,
  value: bigint,
  data: Hex,
  execNonce: bigint,
  chainId: bigint,
  expiry: bigint
): Hex {
  // Calculate struct hash
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
        targetContractAddr,
        value,
        keccak256(data),
        execNonce,
        chainId,
        expiry
      ]
    )
  );

  // Get domain separator
  const domainSeparator = domainSeparatorEigenAgent(eigenAgentAddr, chainId);

  // Calculate the final digest hash
  return keccak256(
    concat([
      toBytes('0x1901'), // EIP-712 prefix      toBytes('0x1901'), // EIP-712 prefix
      toBytes(domainSeparator),
      toBytes(structHash)
    ])
  );
}

/**
 * Create a signature for EigenAgent execution
 * @param client The wallet client to use for signing
 * @param signer The account address to sign with
 * @param eigenAgentAddr EigenAgent contract address
 * @param chainId Chain ID where the transaction will execute
 * @param targetContractAddr Contract to call via the EigenAgent
 * @param messageToEigenlayer Data to send in the call
 * @param execNonce Execution nonce from the EigenAgent
 * @param expiry Timestamp when the signature expires
 * @returns Combined message with signature ready for the EigenAgent
 */
export async function signMessageForEigenAgentExecution(
  client: WalletClient,
  signer: Address,
  eigenAgentAddr: Address,
  chainId: number,
  targetContractAddr: Address,
  messageToEigenlayer: Hex,
  execNonce: bigint,
  expiry: bigint
): Promise<{ signature: Hex, messageWithSignature: Hex }> {
  // Verify parameters
  if (targetContractAddr === '0x0000000000000000000000000000000000000000') {
    throw new Error('Target contract cannot be zero address');
  }
  if (eigenAgentAddr === '0x0000000000000000000000000000000000000000') {
    throw new Error('EigenAgent cannot be zero address');
  }
  if (chainId === 0) {
    throw new Error('Chain ID cannot be zero');
  }

  // Sign the digest using EIP-712
  const signature = await client.signTypedData({
    account: signer,
    domain: {
      name: 'EigenAgent',
      version: TREASURE_RESTAKING_VERSION.substring(0, 2),
      chainId: chainId,
      verifyingContract: eigenAgentAddr
    },
    types: {
      ExecuteWithSignature: [
        { name: 'target', type: 'address' },
        { name: 'value', type: 'uint256' },
        { name: 'data', type: 'bytes' },
        { name: 'execNonce', type: 'uint256' },
        { name: 'chainId', type: 'uint256' },
        { name: 'expiry', type: 'uint256' }
      ]
    },
    primaryType: 'ExecuteWithSignature',
    message: {
      target: targetContractAddr,
      value: 0n,
      data: messageToEigenlayer,
      execNonce: execNonce,
      chainId: BigInt(chainId),
      expiry: expiry
    }
  });

  // Format signature to ensure it has a '0' prefix for the v value
  const formattedSignature = signature.startsWith('0x3') ?
    `0x0${signature.slice(2)}` as Hex :
    signature;

  // This matches the Solidity implementation exactly:
  // messageWithSignature = abi.encodePacked(
  //   messageToEigenlayer,
  //   bytes32(abi.encode(vm.addr(signerKey))), // AgentOwner. Pad signer to 32byte word
  //   expiry,
  //   signatureEigenAgent
  // );

  // Properly encode each part
  const encodedExpiry = encodeAbiParameters([{ type: 'uint256' }], [expiry]);
  const encodedSigner = encodeAbiParameters([{ type: 'address' }], [signer]);

  const messageWithSignature = concat([
    messageToEigenlayer,
    encodedSigner,
    encodedExpiry,
    formattedSignature
  ]) as Hex;

  return {
    signature: formattedSignature,
    messageWithSignature: messageWithSignature
  };
}
