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


#### Verify manually if verify failed in previous step.
# forge verify-contract \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93 0xE4aB69C077896252FAFBD49EFD26B5D171A32410) \
#     --watch \
#     --rpc-url basesepolia \
#     --etherscan-api-key $BASESCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0xFb615DcC9f7AA88657A13055D87bE260446bd89A \
#     ./src/SenderCCIP.sol:SenderCCIP
