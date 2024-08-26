#!/bin/bash
source .env

echo forge script script/3b_upgradeReceiverOnL1.s.sol:DeployReceiverOnL2Script --rpc-url ethsepolia --broadcast --verify -vvvv

forge script script/3b_upgradeReceiverOnL1.s.sol:UpgradeReceiverOnL1Script \
    --rpc-url ethsepolia \
    --broadcast \
    --verify \
    --private-key $DEPLOYER_KEY \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv
