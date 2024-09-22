#!/bin/bash
source .env

echo forge script script/2_deploySenderOnL2.s.sol:DeploySenderOnL2Script --rpc-url basesepolia --broadcast --verify -vvvv

forge script script/2_deploySenderOnL2.s.sol:DeploySenderOnL2Script \
    --rpc-url basesepolia \
    --broadcast \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    --private-key $DEPLOYER_KEY \
    -vvvv


# ## Verify manually if verify failed in previous step.
# forge verify-contract \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93 0xE4aB69C077896252FAFBD49EFD26B5D171A32410) \
#     --watch \
#     --verifier-url https://sepolia.basescan.org/api \
#     --etherscan-api-key $BASESCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0x92EE79732857189A16f5f3139F13c22F1d40C247 \
#     ./src/SenderCCIP.sol:SenderCCIP
