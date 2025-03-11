#!/bin/bash
source .env

echo forge script script/6d_redeposit.s.sol:RedepositScript --rpc-url basesepolia --broadcast -vvvv

forge script script/6d_redeposit.s.sol:RedepositScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv

