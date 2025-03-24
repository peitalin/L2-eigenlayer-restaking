import { Address, keccak256, toBytes } from "viem";

export const DELEGATION_MANAGER_ADDRESS = '0x2604e5a6b77b5Ab95e38b6fA6fc1F5db5585F562' as Address;

export const EIP712_DOMAIN_TYPEHASH = keccak256(
  toBytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
);
