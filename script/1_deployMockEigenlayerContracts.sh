#!/bin/bash
source .env

echo forge script script/1_deployMockEigenlayerContracts.s.sol:DeployMockEigenlayerContractsScript --rpc-url holesky --broadcast -vvvv

forge script script/1_deployMockEigenlayerContracts.s.sol:DeployMockEigenlayerContractsScript \
    --rpc-url holesky \
    --broadcast \
    --verify  \
    --private-key $DEPLOYER_KEY \
    -vvvv

