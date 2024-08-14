#!/bin/bash
source .env

echo forge script script/4_whitelistSenderReceiver.s.sol:WhitelistSenderReceiverScript  --rpc-url ethsepolia --broadcast --verify -vvvv

forge script script/4_whitelistSenderReceiver.s.sol:WhitelistSenderReceiverScript \
    --rpc-url ethsepolia \
    --broadcast \
    --verify \
    -vvvv

