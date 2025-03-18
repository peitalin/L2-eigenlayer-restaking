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
#     --etherscan-api-key $BASESCAN_API_KEY \
#     --compiler-version v0.8.28 \
#     0x08832066A18B3108A613970A24e816cB10bF76c3 \
#     ./src/SenderCCIP.sol:SenderCCIP
