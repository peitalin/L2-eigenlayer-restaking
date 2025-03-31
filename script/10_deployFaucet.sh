#!/bin/bash
source .env

forge script script/10_deployFaucet.s.sol:DeployFaucetScript \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    --verify \
    --etherscan-api-key $BASESCAN_API_KEY \
    -vvvv


# # ## Verify manually if verify failed in previous step.
# forge verify-contract \
#     --watch \
#     --rpc-url basesepolia \
#     --etherscan-api-key $BASESCAN_API_KEY \
#     --compiler-version v0.8.28 \
#     0x3F54080601D2c14Ad7d0A75ccd7CCcf5EC97a8E6 \
#     ./src/utils/Faucet.sol:Faucet

