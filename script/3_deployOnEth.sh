#!/bin/bash
source .env

echo forge script script/3_deployOnEth.s.sol:DeployOnEthScript --rpc-url ethsepolia --broadcast --verify -vvvv

forge script script/3_deployOnEth.s.sol:DeployOnEthScript \
    --rpc-url ethsepolia \
    --broadcast \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --verify \
    -vvvv
    # --private-key $DEPLOYER_KEY \
    # --resume \


### Verify manually if verify failed in previous step
# forge verify-contract \
#     --chain-id 11155111 \
#     --constructor-args $(cast abi-encode "constructor(address,address,address)" 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59 0x779877A7B0D9E8603169DdbD7836e478b4624789 0x71f655CaB647265B0f24C814644e2dD01F9b23e1) \
#     --watch \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x355c6aB76aF980Bb1726eb2e652c19F81B384e5B \
#     ./src/ReceiverCCIP.sol:ReceiverCCIP
