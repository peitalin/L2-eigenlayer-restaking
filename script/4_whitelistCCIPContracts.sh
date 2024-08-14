#!/bin/bash
source .env

echo forge script script/4_whitelistCCIPContracts.s.sol:WhitelistCCIPContractsScript  --rpc-url arbsepolia --broadcast --verify -vvvv

forge script script/4_whitelistCCIPContracts.s.sol:WhitelistCCIPContractsScript \
    --rpc-url arbsepolia \
    --broadcast \
    --verify \
    -vvvv

