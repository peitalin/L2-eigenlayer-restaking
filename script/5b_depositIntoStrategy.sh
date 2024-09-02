#!/bin/bash
source .env

echo forge script script/5b_depositIntoStrategy.s.sol:DepositIntoStrategyScript --rpc-url basesepolia --broadcast -vvvv

forge script script/5b_depositIntoStrategy.s.sol:DepositIntoStrategyScript  \
    --rpc-url basesepolia \
    --broadcast \
    --verify \
    --private-key $DEPLOYER_KEY \
    -vvvv


