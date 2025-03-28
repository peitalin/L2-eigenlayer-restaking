#!/bin/bash
source .env

echo forge script script/1_deployMockEigenlayerContracts.s.sol:DeployMockEigenlayerContractsScript --rpc-url ethsepolia --broadcast -vvvv

forge script script/1_deployMockEigenlayerContracts.s.sol:DeployMockEigenlayerContractsScript \
    --rpc-url ethsepolia \
    --broadcast \
    --verify \
    --gas-estimate-multiplier 200 \
    --private-key $DEPLOYER_KEY \
    -vvvv


# default gas-estimate-multiplier is 130
