import { keccak256, toBytes, Address } from 'viem';
import { toEventSignature } from 'viem';
import { Operator } from '../types';
import { privateKeyToAccount } from 'viem/accounts';

// Chain ID constants
export const ETH_CHAINID = "11155111"; // Ethereum Sepolia
export const L2_CHAINID = "84532";     // Base Sepolia

export const DELEGATION_MANAGER_ADDRESS = (
  process.env.DELEGATION_MANAGER_ADDRESS
  || '0x2604e5a6b77b5Ab95e38b6fA6fc1F5db5585F562'
) as Address;

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

// Event Signatures
export const MESSAGE_SENT_SIGNATURE = keccak256(toBytes(toEventSignature(
  'event MessageSent(bytes32 indexed, uint64 indexed, address, (address, uint256)[], address, uint256)'
)));
// Known value from cast sig-event
export const KNOWN_MESSAGE_SENT_SIGNATURE = '0xf41bc76bbe18ec95334bdb88f45c769b987464044ead28e11193a766ae8225cb';

if (MESSAGE_SENT_SIGNATURE !== KNOWN_MESSAGE_SENT_SIGNATURE) {
  throw new Error('MESSAGE_SENT_SIGNATURE does not match KNOWN_MESSAGE_SENT_SIGNATURE');
}

// Bridge event signatures
export const BRIDGING_WITHDRAWAL_TO_L2_SIGNATURE = keccak256(toBytes(toEventSignature(
  'event BridgingWithdrawalToL2(address,(address,uint256)[])'
)));

export const BRIDGING_REWARDS_TO_L2_SIGNATURE = keccak256(toBytes(toEventSignature(
  'event BridgingRewardsToL2(address,(address,uint256)[])'
)));
