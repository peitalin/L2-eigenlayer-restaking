#!/bin/bash
source .env

echo forge script script/3_deployReceiverOnL1.s.sol:DeployReceiverOnL1Script --rpc-url ethsepolia --broadcast --verify -vvvv

forge script script/3_deployReceiverOnL1.s.sol:DeployReceiverOnL1Script \
    --rpc-url ethsepolia \
    --broadcast \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --private-key $DEPLOYER_KEY \
    --gas-estimate-multiplier 250 \
    --priority-gas-price 200 \
    --verify


# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.28 \
#     0xd1C80a6Ed1FF622832841AeBcf8f109c6c23a9eE \
#     src/6551/EigenAgent6551.sol:EigenAgent6551