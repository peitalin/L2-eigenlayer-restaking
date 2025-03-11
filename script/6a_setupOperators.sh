#!/bin/bash
source .env

echo forge script script/6a_setupOperators.s.sol:SetupOperatorsScript --rpc-url basesepolia --broadcast -vvvv

forge script script/6a_setupOperators.s.sol:SetupOperatorsScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv

