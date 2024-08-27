#!/bin/bash
source .env

echo forge script script/5_depositWithSignature.s.sol:DepositWithSignatureScript --rpc-url basesepolia --broadcast -vvvv

forge script script/5_depositWithSignature.s.sol:DepositWithSignatureScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    --verify \
    -vvvv


### TODO: automatically verify EigenAgent contract after they are spawned
# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x0aEDf2bfF862E2e8D31951E20f329F3776ceF974 \
#     src/6551/EigenAgent6551.sol:EigenAgent6551


## After running this script, search for the TX hash on https://ccip.chain.link/

# We bridge the token from L2 to L1, then deposit into Eigenlayer through 6551 accounts owned by the user, with user signatures:
# [https://ccip.chain.link/msg/0x737def0ecea3e13c47eebe80722a18caa7c8ce64c566044fc3def6da16ee340d](https://ccip.chain.link/msg/0x737def0ecea3e13c47eebe80722a18caa7c8ce64c566044fc3def6da16ee340d)

# On L1, we see the CCIP-BnM token routing through: Sender CCIP (L1 Bridge) -> 6551 Agent -> Eigenlayer Strategy Vault:
# [https://sepolia.etherscan.io/tx/0xbf58d0ce98bdcea9cbe55ce9ff0e3526a2666ddec14b83b293b977f82413ca50](https://sepolia.etherscan.io/tx/0xbf58d0ce98bdcea9cbe55ce9ff0e3526a2666ddec14b83b293b977f82413ca50)

# Gas cost: 0.01396 ETH (approx $36) in (i) bridging, (ii) creating a 6551 EigenAgent, (iii) depositing in Eigenalayer

# and also in the Eigenlayer StrategyManager contract: [https://sepolia.etherscan.io/address/0x7d73d2641d4c68f7b8f11b1ce212645423a0e8b5#events](https://sepolia.etherscan.io/address/0x7d73d2641d4c68f7b8f11b1ce212645423a0e8b5#events)


