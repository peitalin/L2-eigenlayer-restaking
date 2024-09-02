#!/bin/bash
source .env

echo forge script script/5c_mintEigenAgent.s.sol:MintEigenAgentScript --rpc-url basesepolia --broadcast -vvvv

forge script script/5c_mintEigenAgent.s.sol:MintEigenAgentScript  \
    --rpc-url ethsepolia \
    --broadcast \
    --verify \
    --private-key $DEPLOYER_KEY \
    -vvvv
