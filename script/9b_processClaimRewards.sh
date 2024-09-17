#!/bin/bash
source .env

echo forge script script/9b_processClaimRewards.s.sol:ProcessClaimRewardsScript --rpc-url basesepolia --broadcast -vvvv

forge script script/9b_processClaimRewards.s.sol:ProcessClaimRewardsScript \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv
