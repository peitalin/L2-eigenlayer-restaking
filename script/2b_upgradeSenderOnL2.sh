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
#     --compiler-version v0.8.25 \
#     --libraries src/utils/FunctionSelectorDecoder.sol:FunctionSelectorDecoder:0x186af032108ADD15e87b8098ab764376C824f4D5 \
#     0x6D851679b611d5ACE7E3AF9F914507a5B107Af2C \
#     ./src/SenderCCIP.sol:SenderCCIP
