#!/bin/bash
source .env

echo forge script script/2_deployOnArb.s.sol:DeployOnArbScript --rpc-url arbsepolia --broadcast --verify -vvvv

forge script script/2_deployOnArb.s.sol:DeployOnArbScript \
    --rpc-url arbsepolia \
    --broadcast \
    --verify \
    -vvvv


### Verify manually if verify failed in previous step (sometimes happens)
# forge verify-contract \
#     --chain-id 421614 \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E) \
#     --watch \
#     --etherscan-api-key $ARBISCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x713140622eD42e4561c00fBa934a736E3Ba0321C \
#     ./src/SenderCCIP.sol:SenderCCIP