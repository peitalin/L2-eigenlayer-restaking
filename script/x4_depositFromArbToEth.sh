#!/bin/bash
source .env

echo forge script script/x4_depositFromArbToEth.s.sol:DepositFromArbToEthScript --rpc-url arbsepolia --broadcast -vvvv

forge script script/x4_depositFromArbToEth.s.sol:DepositFromArbToEthScript  \
    --rpc-url arbsepolia \
    --broadcast \
    -vvvv


## After running this script, you'll get a TX hash, search for it here:
# https://ccip.chain.link/
## on testnet, it could take up to 30min for Chainlink to bridge:

## Pay with LINK example
# https://ccip.chain.link/msg/0x87788c775295dd642a917758bdc622062d18cfc43c13b10d7955f9fc82836fa5

## Pay with native gas ETH:
# https://ccip.chain.link/msg/0xb8e6351748517d1a37ba28953ef7416dce331393ab7d5ed0c3ee043419bfb894


## Restaking CCIP-BnM token from L2 into Eigenlayer example
# https://ccip.chain.link/msg/0xa2c8e4973ba3fac9378a04bcd438e28e70115c2ae4cd66be9c73ef02d7c28f56
# with associated Eigenlayer deposit events
# https://sepolia.etherscan.io/tx/0xc8fe44c453e8f39949b0e7ff81dbf770790fb92b3fb37a976e1291b1b4deb355#eventlog

# Example 2:
# https://ccip.chain.link/msg/0x9ead55326be80ed9956c97ecd4a7b5a701b3e2dc6921a0672d9f8f8ba978c248
# https://sepolia.etherscan.io/tx/0xee7e78fe09d24dbf7d20010228af21e3011ae0c293f2ce3fd5eba727631453c2#eventlog