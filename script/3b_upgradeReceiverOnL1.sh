#!/bin/bash
source .env

echo forge script script/3b_upgradeReceiverOnL1.s.sol:DeployReceiverOnL2Script --rpc-url holesky --broadcast --verify -vvvv

forge script script/3b_upgradeReceiverOnL1.s.sol:UpgradeReceiverOnL1Script \
    --rpc-url holesky \
    --broadcast \
    --verify \
    --private-key $DEPLOYER_KEY \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv


# forge verify-contract \
#     --watch \
#     --rpc-url holesky \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0xbd1399b675159E2CB25F33f27f6dbdC512aB4005 \
#     ./src/RestakingConnector.sol:RestakingConnector
