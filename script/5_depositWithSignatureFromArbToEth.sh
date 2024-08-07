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
# https://ccip.chain.link/msg/0x8162e2ab7a9a5b3f4ba02d539d4929baf32914a59b24b5b8e9c3815d7a692e48
## with associated Eigenlayer deposit events:
# https://sepolia.etherscan.io/tx/0xd5bfee9bd4786e1a7d259746ad624a70a89d536bf425cf9602d8595b3a66d8b6#eventlog

