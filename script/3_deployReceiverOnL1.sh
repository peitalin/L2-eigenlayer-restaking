#!/bin/bash
source .env

echo forge script script/3_deployReceiverOnL1.s.sol:DeployReceiverOnL1Script --rpc-url ethsepolia --broadcast --verify -vvvv

forge script script/3_deployReceiverOnL1.s.sol:DeployReceiverOnL1Script \
    --rpc-url ethsepolia \
    --broadcast \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --private-key $DEPLOYER_KEY \
    --verify \
    -vvvv


### Verify manually if verify failed in previous step
# forge verify-contract \
#     --watch \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59 0x779877A7B0D9E8603169DdbD7836e478b4624789) \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x89832518b5043d5B31d1a797A06E2717e5EcAFdF \
#     ./src/ReceiverCCIP.sol:ReceiverCCIP


# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x66e79206a5ea3eb7d80ed7fbbaa5240262974594 \
#     ./src/RestakingConnector.sol:RestakingConnector


# forge verify-contract \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x3a0b5a2Ef18e49B8Fb5baF1d2629CC1409f956Cb \
#     ./src/RestakingConnector.sol:RestakingConnector