#!/bin/bash
source .env

echo forge script script/3b_upgradeReceiverOnL1.s.sol:DeployReceiverOnL2Script --rpc-url ethsepolia --broadcast --verify -vvvv

forge script script/3b_upgradeReceiverOnL1.s.sol:UpgradeReceiverOnL1Script \
    --rpc-url ethsepolia \
    --broadcast \
    --verify \
    --private-key $DEPLOYER_KEY \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv


# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.28 \
#     0xBc7bb46EBb6e8658BF6e52349e6E12206Ef710A3 \
#     ./src/RestakingConnector.sol:RestakingConnector
