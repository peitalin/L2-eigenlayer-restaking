import { Address } from 'viem';

// Router ABI for the Chainlink CCIP router
export const ROUTER_ABI = [
  {
    inputs: [
      { name: 'destinationChainSelector', type: 'uint64' },
      {
        name: 'message',
        type: 'tuple',
        components: [
          { name: 'receiver', type: 'bytes' },
          { name: 'data', type: 'bytes' },
          { name: 'tokenAmounts', type: 'tuple[]', components: [
            { name: 'token', type: 'address' },
            { name: 'amount', type: 'uint256' }
          ]},
          { name: 'feeToken', type: 'address' },
          { name: 'extraArgs', type: 'bytes' }
        ]
      }
    ],
    name: 'getFee',
    outputs: [{ name: 'fee', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function'
  }
] as const;

export interface EVMTokenAmount {
  token: Address;
  amount: bigint;
}