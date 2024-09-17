#!/bin/bash
source .env

echo forge script script/9_submitRewards.s.sol:SubmitRewardsScript --rpc-url ethsepolia --broadcast -vvvv

forge script script/9_submitRewards.s.sol:SubmitRewardsScript \
    --rpc-url ethsepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv
