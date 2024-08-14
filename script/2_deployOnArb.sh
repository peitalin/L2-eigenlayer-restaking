#!/bin/bash
source .env

echo forge script script/2_deployOnArb.s.sol:DeployOnArbScript --rpc-url arbsepolia --broadcast --verify -vvvv

forge script script/2_deployOnArb.s.sol:DeployOnArbScript \
    --rpc-url arbsepolia \
    --broadcast \
    --verify \
    --etherscan-api-key $ARBISCAN_API_KEY \
    -vvvv


# ## Verify manually if verify failed in previous step. Arbiscan is unreliable
# forge verify-contract \
#     --chain-id 421614 \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E) \
#     --watch \
#     --etherscan-api-key $ARBISCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0xc6e2a5053715157cd2d87ed29b0de88f7e18cb46 \
#     ./src/SenderCCIP.sol:SenderCCIP


# ## Verify with Sourcify if failed in previous step
# forge verify-contract \
#     --chain-id 421614 \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E) \
#     --watch \
#     --etherscan-api-key $ARBISCAN_API_KEY \
#     --verifier sourcify \
#     --compiler-version v0.8.22 \
#     0xc6e2a5053715157cd2d87ed29b0de88f7e18cb46 \
#     ./src/SenderCCIP.sol:SenderCCIP

# forge verify-check 0xc6e2a5053715157cd2d87ed29b0de88f7e18cb46 \
#   --chain-id 421614 \
#   --verifier sourcify

# https://sourcify.dev/#/lookup/0xc6e2A5053715157cd2D87ED29B0dE88F7E18Cb46
