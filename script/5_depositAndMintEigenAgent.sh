#!/bin/bash
source .env

echo forge script script/5_depositAndMintEigenAgent.s.sol:DepositAndMintEigenAgentScript --rpc-url basesepolia --broadcast -vvvv

forge script script/5_depositAndMintEigenAgent.s.sol:DepositAndMintEigenAgentScript  \
    --rpc-url basesepolia \
    --broadcast \
    --verify \
    --private-key $DEPLOYER_KEY \
    -vvvv


### TODO: automatically verify EigenAgent contract after they are spawned
# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0x0aEDf2bfF862E2e8D31951E20f329F3776ceF974 \
#     src/6551/EigenAgent6551.sol:EigenAgent6551


## After running this script, search for the TX hash on https://ccip.chain.link/

# We bridge the token from L2 to L1, then deposit into Eigenlayer through 6551 accounts owned by the user, with user signatures:
# [https://ccip.chain.link/msg/0x025b854ed6d4c0af1b2c8cf696fb3f310702492cdbe2618135dacf4d74208e2b](https://ccip.chain.link/msg/0x025b854ed6d4c0af1b2c8cf696fb3f310702492cdbe2618135dacf4d74208e2b)

# On L1, we see the CCIP-BnM token routing through: Sender CCIP (L1 Bridge) -> 6551 Agent -> Eigenlayer Strategy Vault:
# [https://sepolia.etherscan.io/tx/0x55580c6681525f385198639814f1e54e9213c613cdcdef806e89e9403f3f3c9a](https://sepolia.etherscan.io/tx/0x55580c6681525f385198639814f1e54e9213c613cdcdef806e89e9403f3f3c9a)

# Gas cost estimate in (i) bridging, (ii) creating a 6551 EigenAgent, (iii) depositing in Eigenalayer
# most of the gas cost is in creating the 6551 EigenAgent (1.8mil gas)

# and also in the Eigenlayer StrategyManager contract: [https://sepolia.etherscan.io/address/0x7d73d2641d4c68f7b8f11b1ce212645423a0e8b5#events](https://sepolia.etherscan.io/address/0x7d73d2641d4c68f7b8f11b1ce212645423a0e8b5#events)




