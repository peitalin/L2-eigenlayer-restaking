import { Address, keccak256, toBytes } from "viem";

export const L1_CHAIN_ID = 11155111;

export const DELEGATION_MANAGER_ADDRESS = '0x2604e5a6b77b5Ab95e38b6fA6fc1F5db5585F562' as Address;

// /// @notice The EIP-712 typehash for the `DelegationApproval` struct used by the contract
// bytes32 public constant DELEGATION_APPROVAL_TYPEHASH = keccak256(
//     "DelegationApproval(address delegationApprover,address staker,address operator,bytes32 salt,uint256 expiry)"
// );
export const DELEGATION_APPROVAL_TYPEHASH = keccak256(
  toBytes('DelegationApproval(address delegationApprover,address staker,address operator,bytes32 salt,uint256 expiry)')
);

export const EIP712_DOMAIN_TYPEHASH = keccak256(
  toBytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
);
