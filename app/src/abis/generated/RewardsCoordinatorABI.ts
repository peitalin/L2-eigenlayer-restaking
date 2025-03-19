import { Address } from 'viem';

export const RewardsCoordinatorABI = [
  // Function to get distribution roots length
  {
    inputs: [],
    name: 'getDistributionRootsLength',
    outputs: [{ internalType: 'uint256', name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  // Function to get current distribution root
  {
    inputs: [],
    name: 'getCurrentDistributionRoot',
    outputs: [
      {
        components: [
          { internalType: 'bytes32', name: 'distRootHash', type: 'bytes32' },
          { internalType: 'uint256', name: 'claimableEndBlock', type: 'uint256' },
          { internalType: 'bytes32', name: 'earnerAndTokenRoot', type: 'bytes32' },
          { internalType: 'uint256', name: 'totalEarningsDistributed', type: 'uint256' },
          { internalType: 'uint32', name: 'totalEarnerTokenLeaves', type: 'uint32' },
          { internalType: 'uint32', name: 'tokenCount', type: 'uint32' },
        ],
        internalType: 'struct IRewardsCoordinator.DistributionRoot',
        name: '',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  // Function to calculate token leaf hash
  {
    inputs: [
      {
        components: [
          { internalType: 'address', name: 'token', type: 'address' },
          { internalType: 'uint256', name: 'cumulativeEarnings', type: 'uint256' },
        ],
        internalType: 'struct IRewardsCoordinatorTypes.TokenTreeMerkleLeaf',
        name: 'tokenLeaf',
        type: 'tuple',
      },
    ],
    name: 'calculateTokenLeafHash',
    outputs: [{ internalType: 'bytes32', name: '', type: 'bytes32' }],
    stateMutability: 'pure',
    type: 'function',
  },
  // Function to process claim
  {
    inputs: [
      {
        components: [
          { internalType: 'uint32', name: 'rootIndex', type: 'uint32' },
          { internalType: 'uint32', name: 'earnerIndex', type: 'uint32' },
          { internalType: 'bytes', name: 'earnerTreeProof', type: 'bytes' },
          {
            components: [
              { internalType: 'address', name: 'earner', type: 'address' },
              { internalType: 'bytes32', name: 'earnerTokenRoot', type: 'bytes32' },
            ],
            internalType: 'struct IRewardsCoordinatorTypes.EarnerTreeMerkleLeaf',
            name: 'earnerLeaf',
            type: 'tuple',
          },
          { internalType: 'uint32[]', name: 'tokenIndices', type: 'uint32[]' },
          { internalType: 'bytes[]', name: 'tokenTreeProofs', type: 'bytes[]' },
          {
            components: [
              { internalType: 'address', name: 'token', type: 'address' },
              { internalType: 'uint256', name: 'cumulativeEarnings', type: 'uint256' },
            ],
            internalType: 'struct IRewardsCoordinatorTypes.TokenTreeMerkleLeaf[]',
            name: 'tokenLeaves',
            type: 'tuple[]',
          },
        ],
        internalType: 'struct IRewardsCoordinatorTypes.RewardsMerkleClaim',
        name: 'claim',
        type: 'tuple',
      },
      { internalType: 'address', name: 'recipient', type: 'address' },
    ],
    name: 'processClaim',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const;