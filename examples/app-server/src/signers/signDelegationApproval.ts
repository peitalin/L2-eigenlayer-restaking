import { privateKeyToAccount } from 'viem/accounts';
import { keccak256, toBytes, concat, encodeAbiParameters, Hex, Address, createPublicClient, http } from 'viem';
import { sepolia } from 'viem/chains';
import {
  DELEGATION_MANAGER_ADDRESS,
  EIP712_DOMAIN_TYPEHASH,
  DELEGATION_APPROVAL_TYPEHASH,
  ETH_CHAINID,
  L2_CHAINID
} from '../utils/constants';
import logger from '../utils/logger';

const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(process.env.SEPOLIA_RPC_URL || 'https://sepolia.drpc.org')
});

interface SignDelegationApprovalResult {
  signature: string;
  digestHash: string;
  salt: string;
  expiry: string;
  delegationManagerAddress: string;
  chainId: string;
}

export async function signDelegationApproval(
  staker: string,
  approver: string,
  operatorKey: `0x${string}`,
  expiry: bigint,
  testSalt?: Hex | undefined,
): Promise<SignDelegationApprovalResult> {
  try {
    // Create account from private key
    const operatorAccount = privateKeyToAccount(operatorKey);
    // Generate a random salt
    const salt: Hex = !!testSalt
      ? testSalt
      : keccak256(toBytes(Date.now().toString() + Math.random().toString()));

    logger.debug("========= Signing Delegation Approval==========");
    logger.debug({
      staker,
      approver,
      operator: operatorAccount.address,
      expiry,
      salt
    });

    if (staker === approver) {
      throw new Error("Staker and approver cannot be the same");
    }

    // Use the EthSepolia chain ID and delegation manager address
    const chainId = ETH_CHAINID; // Ethereum Sepolia
    const delegationManagerAddress = DELEGATION_MANAGER_ADDRESS;

    // Get digest hash directly from the contract
    const digestHash = await callContractCalculateDelegationApprovalDigestHash(
      staker as Address,
      operatorAccount.address as Address,
      approver as Address,
      salt,
      expiry
    );

    const manualDigestHash = calculateDelegationApprovalDigestHash(
      staker as Address,
      operatorAccount.address as Address,
      approver as Address,
      salt,
      expiry,
      BigInt(chainId)
    );

    // If digests don't match, throw error
    if (digestHash !== manualDigestHash) {
      logger.debug("Contract digest hash:", digestHash);
      logger.debug("Manual digest hash:", manualDigestHash);
      logger.debug("Digests match:", digestHash === manualDigestHash);
      logger.error("Digest hash mismatch between contract and manual calculation");
      logger.error("Contract params: staker, operator, approver, salt, expiry", staker, operatorAccount.address, approver, salt, expiry.toString());
    }

    // Sign the digest hash directly using sign() not signMessage()
    // Otherwise signMessage() automatically adds a EIP-191 prefix which won't
    // match the signatures used in DelegationManager.sol in Eigenlayer
    const signature = await operatorAccount.sign({
      hash: digestHash
    });

    return {
      signature,
      digestHash,
      salt,
      expiry: expiry.toString(),
      delegationManagerAddress,
      chainId: chainId.toString()
    };
  } catch (error: unknown) {
    if (error instanceof Error) {
      logger.error('Error signing delegation approval:', error.message);
      throw error;
    }
    throw new Error('Unknown error occurred while signing delegation approval');
  }
}


/**
 * Calls the calculateDelegationApprovalDigestHash function directly on the DelegationManager contract
 * @param staker The staker address
 * @param operator The operator address
 * @param delegationApprover The delegation approver address
 * @param salt The approval salt
 * @param expiry The expiry timestamp
 * @returns Promise resolving to the digest hash from the contract
 */
export async function callContractCalculateDelegationApprovalDigestHash(
  staker: Address,
  operator: Address,
  delegationApprover: Address,
  salt: Hex,
  expiry: bigint
): Promise<Hex> {
  try {
    // Log all parameters to help diagnose

    // Call the contract's calculateDelegationApprovalDigestHash function
    const digestHash = await publicClient.readContract({
      address: DELEGATION_MANAGER_ADDRESS,
      abi: [
        {
          name: 'calculateDelegationApprovalDigestHash',
          type: 'function',
          stateMutability: 'view',
          inputs: [
            { name: 'staker', type: 'address' },
            { name: 'operator', type: 'address' },
            { name: 'approver', type: 'address' },
            { name: 'approverSalt', type: 'bytes32' },
            { name: 'expiry', type: 'uint256' }
          ],
          outputs: [{ name: '', type: 'bytes32' }]
        }
      ],
      functionName: 'calculateDelegationApprovalDigestHash',
      args: [staker, operator, delegationApprover, salt, expiry]
    });

    return digestHash as Hex;
  } catch (error) {
    logger.error('Error calling calculateDelegationApprovalDigestHash on contract:', error);
    throw new Error('Failed to call calculateDelegationApprovalDigestHash on contract');
  }
}


function calculateDelegationApprovalDigestHash(
  staker: Address,
  operator: Address,
  approver: Address,
  salt: Hex,
  expiry: bigint,
  chainId: bigint
): Hex {

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
        keccak256(toBytes('EigenLayer')),
        keccak256(toBytes('v1')), // major version (Eigenlayer is currently on v1.3.0)
        BigInt(chainId),
        DELEGATION_MANAGER_ADDRESS
      ]
    )
  );

  const approverStructHash = keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'address' },
        { type: 'address' },
        { type: 'address' },
        { type: 'bytes32' },
        { type: 'uint256' }
      ],
      [
        DELEGATION_APPROVAL_TYPEHASH,
        approver as Address, // delegationApprover is the operator in this case
        staker as Address,
        operator as Address, // operator
        salt,
        expiry
      ]
    )
  );

  const manualDigestHash = keccak256(
    concat([
      toBytes('0x1901'),
      toBytes(domainSeparator),
      toBytes(approverStructHash)
    ])
  );

  return manualDigestHash;
}