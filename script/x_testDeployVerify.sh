#!/bin/bash
source .env

echo forge script script/x_testDeployVerify.s.sol:TestDeployVerifyScript --rpc-url ethsepolia --broadcast -vvvv

forge script script/x_testDeployVerify.s.sol:TestDeployVerifyScript \
    --rpc-url ethsepolia \
    --broadcast \
    --verify  \
    --private-key $DEPLOYER_KEY \
    -vvvv

