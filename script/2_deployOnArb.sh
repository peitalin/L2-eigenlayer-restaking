#!/bin/bash
source .env

echo forge script script/2_deployOnArb.s.sol:DeployOnArbScript --rpc-url arbsepolia --broadcast --verify -vvvv

forge script script/2_deployOnArb.s.sol:DeployOnArbScript \
    --rpc-url arbsepolia \
    --broadcast \
    --verify \
    --etherscan-api-key $ARBISCAN_API_KEY \
    -vvvv


### Deploys + verifies on Etherscan, so Arbiscan is the problem
# https://sepolia.etherscan.io/address/0xce3b2896008f8140a763f3f53943195b8589a10c#code



# ## Verify manually if verify failed in previous step. Arbiscan is unreliable
# forge verify-contract \
#     --chain-id 421614 \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E) \
#     --watch \
#     --etherscan-api-key $ARBISCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x06b72b50b23fecd190d6fec7b1b99c9f7b6a3e0f \
#     ./src/SenderCCIP.sol:SenderCCIP


####### Verify with Sourcify
# forge verify-contract \
#     --chain-id 421614 \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E) \
#     --watch \
#     --etherscan-api-key $ARBISCAN_API_KEY \
#     --verifier sourcify \
#     --compiler-version v0.8.22 \
#     0x06b72b50b23fecd190d6fec7b1b99c9f7b6a3e0f \
#     ./src/SenderCCIP.sol:SenderCCIP

# forge verify-check 0x06b72b50b23fecd190d6fec7b1b99c9f7b6a3e0f \
#   --chain-id 421614 \
#   --verifier sourcify

# https://sourcify.dev/#/lookup/0x06b72b50b23fecd190d6fec7b1b99c9f7b6a3e0f
