import {
  Address, Hex, Hash, concat,
  encodeAbiParameters, keccak256, encodePacked,
  toBytes, WalletClient,
  verifyMessage, SignableMessage, verifyTypedData,
  stringToHex, hexToBytes, bytesToHex, hexToString
} from 'viem';
import { EthSepolia } from '../addresses';
import { ZeroAddress } from './encoders';

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

  console.log("targetContractAddr", targetContractAddr);
  console.log("eigenAgentAddr", eigenAgentAddr);
  console.log("messageToEigenlayer", messageToEigenlayer);
  console.log("execNonce", execNonce);
  console.log("chainid", targetChainId);
  console.log("expiry", expiry);
  console.log("--------------");
  console.log("agentOwner/signer", signer);

  // encode and pad signer to 32byte word
  const encodedExpiry = encodeAbiParameters([{ type: 'uint256' }], [expiry]);
  const encodedSigner = encodeAbiParameters([{ type: 'address' }], [signer]);

  console.log("\ndigestHash", digestHash);
  console.log("signature", formattedSignature);

  // match the Solidity implementation:
  // messageWithSignature = abi.encodePacked(
  //   messageToEigenlayer,
  //   bytes32(abi.encode(vm.addr(signerKey))), // AgentOwner. Pad signer to 32byte word
  //   expiry,
  //   signatureEigenAgent
  // );
  const messageWithSignature = concat([
    messageToEigenlayer,
    encodedSigner,
    encodedExpiry,
    formattedSignature
  ]) as Hex;
  // const messageWithSignature = encodePacked(
  //   ['bytes', 'address', 'uint256', 'bytes'],
  //   [messageToEigenlayer, encodedSigner, encodedExpiry, formattedSignature]
  // )

  return {
    signature: formattedSignature,
    messageWithSignature: messageWithSignature
  };
}
