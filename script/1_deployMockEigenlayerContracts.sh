#!/bin/bash
source .env

echo forge script script/1_deployMockEigenlayerContracts.s.sol:DeployMockEigenlayerContractsScript --rpc-url ethsepolia --broadcast -vvvv

forge script script/1_deployMockEigenlayerContracts.s.sol:DeployMockEigenlayerContractsScript \
    --rpc-url ethsepolia \
    --broadcast \
    --verify  \
    --private-key $DEPLOYER_KEY \
    -vvvv

echo "uncomment --private-key to deploy Eigenlayer contracts (~11 contracts)"
