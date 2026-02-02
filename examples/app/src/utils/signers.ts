import {
  Address, Hex, Hash, concat,
  encodeAbiParameters, keccak256, encodePacked,
  toBytes, WalletClient,
} from 'viem';

import { EthSepolia, BaseSepolia, DELEGATION_MANAGER_ADDRESS, STRATEGY, STRATEGY_MANAGER_ADDRESS } from '../addresses';
import { ZeroAddress } from './encoders';
import { SERVER_BASE_URL } from '../configs';
import { DelegationManagerABI, StrategyManagerABI } from '../abis';

// Constants from ClientSigners.sol
export const EIGEN_AGENT_EXEC_TYPEHASH = keccak256(
  toBytes("ExecuteWithSignature(address target,uint256 value,bytes data,uint256 execNonce,uint256 chainId,uint256 expiry)")
);
export const EIP712_DOMAIN_TYPEHASH = keccak256(
  toBytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
);
export const TREASURE_RESTAKING_VERSION = "v1.0.0";

// Delegation approval typehash
export const DELEGATION_APPROVAL_TYPEHASH = keccak256(
  toBytes("DelegationApproval(address delegationApprover,address staker,address operator,bytes32 salt,uint256 expiry)")
);

/**
 * Creates a domain separator for EigenAgent contract
 * @param contractAddr EigenAgent contract address
 * @param chainId Chain ID where the EigenAgent is deployed
 * @returns Domain separator hash
 */
export function domainSeparatorEigenAgent(contractAddr: Address, chainId: bigint): Hash {
  // Get the major version (v1) from v1.0.0
  const majorVersion = TREASURE_RESTAKING_VERSION.substring(0, 2);
  // Calculate domain separator, same as Solidity
  // keccak256(
  //     abi.encode(
  //         EIP712_DOMAIN_TYPEHASH,
  //         keccak256(bytes("EigenAgent")),
  //         keccak256(bytes(_majorVersionEigenAgent())),
  //         destinationChainid,
  //         contractAddr
  //     )
  // );
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
  // bytes32 structHash = keccak256(abi.encode(
  //     EIGEN_AGENT_EXEC_TYPEHASH,
  //     _target,
  //     _value,
  //     keccak256(_data),
  //     _nonce,
  //     _chainid,
  //     _expiry
  // ));
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
  // bytes32 digestHash = keccak256(abi.encodePacked(
  //     "\x19\x01",
  //     domainSeparatorEigenAgent(_eigenAgent, _chainid),
  //     structHash
  // ));
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
  targetContractAddr: Address,
  messageToEigenlayer: Hex,
  execNonce: bigint,
  expiry: bigint
): Promise<{ signature: Hex, messageWithSignature: Hex }> {
  // Verify parameters
  if (targetContractAddr === ZeroAddress) {
    throw new Error('Target contract cannot be zero address');
  }
  if (eigenAgentAddr === ZeroAddress) {
    throw new Error('EigenAgent cannot be zero address');
  }
  let targetChainId = Number(EthSepolia.chainId);
  if (TREASURE_RESTAKING_VERSION.substring(0, 2) !== 'v1') {
    throw new Error('Invalid TREASURE_RESTAKING_VERSION');
  }

  // Create the digest hash manually using our function
  const digestHash = createEigenAgentCallDigestHash(
    targetContractAddr,
    eigenAgentAddr,
    0n, // value (0 for token transfers)
    messageToEigenlayer,
    execNonce,
    BigInt(targetChainId), // target chain where EigenAgent is
    expiry
  );

  // Sign the digest hash directly using signMessage
  // This automatically adds a EIP-191 prefix, so no need to
  // process the digestHash as we do in the solidity version in ClientSigners.sol
  const signature = await client.signMessage({
    account: signer,
    message: { raw: digestHash }
  });

  // Format signature to ensure it has the correct length
  // Standard Ethereum signature is 65 bytes: r (32 bytes) + s (32 bytes) + v (1 byte)
  // As a hex string with 0x prefix: 2 + 64 + 64 + 2 = 132 characters
  let formattedSignature: Hex;

  if (signature.length === 132) {
    // Signature already has the correct length, keep it as is
    formattedSignature = signature;
  } else {
    // Viem returns a signature with a '3' prefix for some reason
    // and it was the wrong length (len=130)
    formattedSignature = `0x0${signature.slice(2)}` as Hex;
  }

  // encode and pad signer to 32byte word
  const paddedSigner = encodeAbiParameters([{ type: 'address' }], [signer]);

  // match the Solidity implementation:
  // messageWithSignature = abi.encodePacked(
  //   messageToEigenlayer,
  //   bytes32(abi.encode(vm.addr(signerKey))), // AgentOwner. Pad signer to 32byte word
  //   expiry,
  //   signatureEigenAgent
  // );
  const messageWithSignature = encodePacked(
    ['bytes', 'bytes32', 'uint256', 'bytes'],
    [messageToEigenlayer, paddedSigner, expiry, formattedSignature]
  );

  return {
    signature: formattedSignature,
    messageWithSignature: messageWithSignature
  };
}

interface SignDelegationApprovalResult {
  signature: string;
  digestHash: string;
  salt: string;
  expiry: string;
  delegationManagerAddress: string;
  chainId: string;
}

export async function signDelegationApprovalServer(
  staker: `0x${string}`,
  operator: `0x${string}`,
  publicClient: any
): Promise<SignDelegationApprovalResult> {
  try {
    // Call the server API for delegation approval
    const response = await fetch(`${SERVER_BASE_URL}/api/delegation/sign`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        staker,
        operator
      }),
    });

    if (!response.ok) {
      throw new Error(`Server responded with status: ${response.status}`);
    }

    // Parse the server response
    const data = await response.json() as SignDelegationApprovalResult;

    try {
      // Call the contract's function with the same parameters
      const contractDigestHash = await callContractCalculateDelegationApprovalDigestHash(
        staker as Address,
        operator as Address,
        operator as Address, // operator is also the delegationApprover in our case
        data.salt as Hex,
        BigInt(data.expiry),
        publicClient
      );
      // Log comparison of the digests
      if (data.digestHash !== contractDigestHash) {
        // Log detailed information for debugging
        console.log('Server delegation approval data:', data);
        console.log("staker:", staker);
        console.log("operator:", operator);
        console.log("salt:", data.salt);
        console.log("expiry:", data.expiry);
        console.log('Server digest hash:', data.digestHash);
        console.log('Contract digest hash:', contractDigestHash);
        console.log('Digests match:', data.digestHash === contractDigestHash);
        throw new Error('Digest hash mismatch');
      }

      // Also log the signature from the server
      console.log('Server signature:', data.signature);
    } catch (compareError) {
      console.error('Error comparing digest hashes:', compareError);
      // Don't fail the overall function if comparison fails
    }

    return data;
  } catch (error) {
    console.error('Error signing delegation approval:', error);
    throw new Error('Failed to sign delegation approval');
  }
}

/**
 * Calls the calculateDelegationApprovalDigestHash function directly on the DelegationManager contract
 * @param staker The staker address
 * @param operator The operator address
 * @param delegationApprover The delegation approver address
 * @param salt The approval salt
 * @param expiry The expiry timestamp
 * @param publicClient The Ethereum public client
 * @returns Promise resolving to the digest hash from the contract
 */
export async function callContractCalculateDelegationApprovalDigestHash(
  staker: Address,
  operator: Address,
  delegationApprover: Address,
  salt: Hex,
  expiry: bigint,
  publicClient: any
): Promise<Hex> {
  try {

    if (staker === delegationApprover) {
      throw new Error("Staker and approver cannot be the same");
    }

    // Call the contract's calculateDelegationApprovalDigestHash function
    const digestHash = await publicClient.readContract({
      address: DELEGATION_MANAGER_ADDRESS,
      abi: DelegationManagerABI,
      functionName: 'calculateDelegationApprovalDigestHash',
      args: [staker, operator, delegationApprover, salt, expiry]
    });

    return digestHash as Hex;
  } catch (error) {
    console.error('Error calling calculateDelegationApprovalDigestHash on contract:', error);
    throw new Error('Failed to call calculateDelegationApprovalDigestHash on contract');
  }
}



// Add declaration for window.ethereum
declare global {
  interface Window {
    ethereum?: any;
  }
}