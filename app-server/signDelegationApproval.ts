import { privateKeyToAccount } from 'viem/accounts';
import { keccak256, toBytes, concat, encodeAbiParameters, Hex, Address } from 'viem';
import { DELEGATION_MANAGER_ADDRESS, EIP712_DOMAIN_TYPEHASH } from './constants.js';

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
  operator: string,
  operatorKey: `0x${string}`,
  expiry: bigint,
  testSalt?: Hex | undefined,
): Promise<SignDelegationApprovalResult> {
  try {
    // Create account from private key
    const operatorAccount = privateKeyToAccount(operatorKey);
    console.log("operatorAccount", operatorAccount.address);

    // Generate a random salt
    const salt: Hex = !!testSalt
      ? testSalt
      : keccak256(toBytes(Date.now().toString() + Math.random().toString()));
    console.log("salt", salt);

    // Use the EthSepolia chain ID and delegation manager address
    const chainId = 11155111; // Ethereum Sepolia
    const delegationManagerAddress = DELEGATION_MANAGER_ADDRESS;

    // Calculate the digest hash
    const delegationTypehash = keccak256(
      toBytes('DelegationApproval(address delegationApprover,address staker,address operator,bytes32 salt,uint256 expiry)')
    );

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
          delegationManagerAddress as `0x${string}`
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
          delegationTypehash,
          operator as `0x${string}`, // delegationApprover is the operator in this case
          staker as `0x${string}`,
          operator as `0x${string}`,
          salt,
          expiry
        ]
      )
    );

    const digestHash = keccak256(
      concat([
        toBytes('0x1901'),
        toBytes(domainSeparator),
        toBytes(approverStructHash)
      ])
    );

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
      console.error('Error signing delegation approval:', error.message);
      throw error;
    }
    throw new Error('Unknown error occurred while signing delegation approval');
  }
}