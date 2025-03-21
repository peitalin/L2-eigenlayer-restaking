#!/bin/bash
source .env

echo forge script script/1_setupRealEigenlayerContracts.s.sol:SetupRealEigenlayerContractsScript --rpc-url ethsepolia --broadcast -vvvv

forge script script/1_setupRealEigenlayerContracts.s.sol:SetupRealEigenlayerContractsScript \
    --rpc-url ethsepolia \
    --broadcast \
    --verify  \
    --private-key $DEPLOYER_KEY \
    --priority-gas-price 250 \
    -vvvv


# default gas-estimate-multiplier is 130
