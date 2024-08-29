#!/bin/bash
source .env

echo forge script script/4_whitelistCCIPContracts.s.sol:WhitelistCCIPContractsScript  --rpc-url basesepolia --broadcast --verify -vvvv

forge script script/4_whitelistCCIPContracts.s.sol:WhitelistCCIPContractsScript \
    --rpc-url basesepolia \
    --broadcast \
    --verify \
    --private-key $DEPLOYER_KEY \
    -vvvv

