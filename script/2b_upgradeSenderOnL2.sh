#!/bin/bash
source .env

echo forge script script/2b_upgradeSenderOnL2.s.sol:UpgradeSenderOnL2Script --rpc-url basesepolia --broadcast --verify -vvvv

forge script script/2b_upgradeSenderOnL2.s.sol:UpgradeSenderOnL2Script \
    --rpc-url basesepolia \
    --broadcast \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    --private-key $DEPLOYER_KEY \
    -vvvv


## Verify manually if verify failed in previous step.
# forge verify-contract \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93 0xE4aB69C077896252FAFBD49EFD26B5D171A32410) \
#     --watch \
#     --verifier-url https://sepolia.basescan.org/api \
#     --etherscan-api-key $BASESCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x95bA1749619C81E70f3eF276Ce8A392747e32aE4 \
#     ./src/SenderCCIP.sol:SenderCCIP

# forge verify-contract \
#     --chain-id 421614 \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E) \
#     --watch \
#     --etherscan-api-key $ARBISCAN_API_KEY \
#     --verifier sourcify \
#     --compiler-version v0.8.22 \
#     0x8f65e1a6b4e3a4566c52f9cd4ea160b12bbd51f0 \
#     ./src/SenderCCIP.sol:SenderCCIP
# https://sourcify.dev/#/lookup/0x8f65e1a6b4e3a4566c52f9cd4ea160b12bbd51f0