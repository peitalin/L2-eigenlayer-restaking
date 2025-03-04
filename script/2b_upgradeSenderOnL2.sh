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

