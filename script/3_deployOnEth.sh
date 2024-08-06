#!/bin/bash
source .env

echo forge script script/3_deployOnEth.s.sol:DeployOnEthScript --rpc-url ethsepolia --broadcast --verify -vvvv

forge script script/3_deployOnEth.s.sol:DeployOnEthScript \
    --rpc-url ethsepolia \
    --broadcast \
    --verify \
    -vvvv


### Verify manually if verify failed in previous step (sometimes happens)
# forge verify-contract \
#     --chain-id 11155111 \
#     --constructor-args $(cast abi-encode "constructor(address,address,address)" 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59 0x779877A7B0D9E8603169DdbD7836e478b4624789 0x71f655CaB647265B0f24C814644e2dD01F9b23e1) \
#     --watch \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x5C95b4EC7c08527F172842dB0a79127ABBf9BfD3 \
#     ./src/ReceiverCCIP.sol:ReceiverCCIP
