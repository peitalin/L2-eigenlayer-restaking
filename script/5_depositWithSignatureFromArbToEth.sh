#!/bin/bash
source .env

echo forge script script/5_depositWithSignatureFromArbToEth.s.sol:DepositWithSignatureFromArbToEthScript --rpc-url arbsepolia --broadcast -vvvv

forge script script/5_depositWithSignatureFromArbToEth.s.sol:DepositWithSignatureFromArbToEthScript  \
    --rpc-url arbsepolia \
    --broadcast \
    -vvvv

## After running this script, search for the TX hash on https://ccip.chain.link/
## On testnet, it can take ~30min for Chainlink to bridge.

## Example 1:
## Restaking CCIP-BnM token from L2 into Eigenlayer example (with staker signatures)
# https://ccip.chain.link/msg/0xffea9be16502ed6ce6d1c9993d99dbad93a947bef0dc7f8fce8d608e8529972e
## with associated Eigenlayer deposit events:
# https://sepolia.etherscan.io/tx/0xae4d9c3c81d77f15405bdfc6e7a018389c7ff6911b9e6b6fbc8048cfe32393f3#eventlog

## Example 2:
## Restaking CCIP-BnM token from L2 into Eigenlayer example (with staker signatures)
# https://ccip.chain.link/msg/0x8162e2ab7a9a5b3f4ba02d539d4929baf32914a59b24b5b8e9c3815d7a692e48
## with associated Eigenlayer deposit events:
# https://sepolia.etherscan.io/tx/0xd5bfee9bd4786e1a7d259746ad624a70a89d536bf425cf9602d8595b3a66d8b6#eventlog

