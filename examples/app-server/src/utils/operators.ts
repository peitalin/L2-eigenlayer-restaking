import { Operator } from '../types';
import { privateKeyToAccount } from 'viem/accounts';

// Operator data
export const OPERATORS_DATA: Operator[] = [
  {
    address: '0xA4D423ED017F063AaF65f6B6B9C6Bc59f97d5164',
    name: 'Treasure Node 1',
    magicStaked: '1,250,000',
    ethStaked: '432.5',
    stakers: 42,
    fee: '1%',
    isActive: true
  },
  {
    address: '0xaA61cC14ac3e048f26b9312E57ECf8156D9D27e3',
    name: 'Treasure Node2',
    magicStaked: '890,500',
    ethStaked: '122.2',
    stakers: 36,
    fee: '2%',
    isActive: true
  },
  {
    address: '0x3d2FB9D26c5C66D0CA55247E4d40Cb4FBe0f5C03',
    name: "Inactive Operator",
    magicStaked: '2,100,000',
    ethStaked: '95.8',
    stakers: 65,
    fee: '4%',
    isActive: false
  }
];

// Create a map to quickly look up operators by address
export const operatorsByAddress = new Map<string, Operator>();
OPERATORS_DATA.forEach(operator => {
  operatorsByAddress.set(operator.address.toLowerCase(), operator);
});

// Load operator keys from environment variables
const OPERATOR_KEYS: { [key: string]: string | undefined } = {};
for (let i = 1; i <= 10; i++) {
  const keyName = `OPERATOR_KEY${i}`;
  if (process.env[keyName]) {
    OPERATOR_KEYS[keyName] = process.env[keyName];
  }
}

// Validate that at least one operator key is set
if (Object.keys(OPERATOR_KEYS).length === 0) {
  console.warn('Warning: No operator keys found in environment variables (OPERATOR_KEY1 through OPERATOR_KEY10)');
}

// Create a map of operator addresses to their private keys
export const operatorAddressToKey = new Map<string, string>();

// Initialize operator addresses
Object.entries(OPERATOR_KEYS).forEach(([keyName, privateKey]) => {
  if (privateKey) {
    try {
      const account = privateKeyToAccount(privateKey as `0x${string}`);
      operatorAddressToKey.set(account.address.toLowerCase(), privateKey);
      console.log(`Initialized operator ${keyName} with address ${account.address}`);
    } catch (error) {
      console.error(`Error initializing operator account for ${keyName}:`, error);
    }
  }
});

