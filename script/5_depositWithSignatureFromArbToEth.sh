#!/bin/bash
source .env

echo forge script script/5_depositWithSignatureFromArbToEth.s.sol:DepositWithSignatureFromArbToEthScript --rpc-url arbsepolia --broadcast -vvvv

forge script script/5_depositWithSignatureFromArbToEth.s.sol:DepositWithSignatureFromArbToEthScript  \
    --rpc-url arbsepolia \
    --broadcast \
    -vvvv

## After running this script, you'll get a TX hash, search for it here:
# https://ccip.chain.link/
## on testnet, it could take up to 30min for Chainlink to bridge:


## Restaking CCIP-BnM token from L2 into Eigenlayer example (with staker signatures)
# https://ccip.chain.link/msg/0x4fe5611cf4bc8eaf4397f52f7cd5d14aa0d3c814d72009b4ec2503b8e72c3e6d
## with associated Eigenlayer deposit events
