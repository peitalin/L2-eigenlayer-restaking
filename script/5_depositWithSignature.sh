#!/bin/bash
source .env

echo forge script script/5_depositWithSignature.s.sol:DepositWithSignatureScript --rpc-url basesepolia --broadcast -vvvv

forge script script/5_depositWithSignature.s.sol:DepositWithSignatureScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv

## After running this script, search for the TX hash on https://ccip.chain.link/

## Example 1:
## Restaking CCIP-BnM token from L2 into Eigenlayer example (with staker signatures)
# https://ccip.chain.link/msg/0xffea9be16502ed6ce6d1c9993d99dbad93a947bef0dc7f8fce8d608e8529972e
## with associated Eigenlayer deposit events:
# https://sepolia.etherscan.io/tx/0xae4d9c3c81d77f15405bdfc6e7a018389c7ff6911b9e6b6fbc8048cfe32393f3#eventlog

## Example 2:
## Restaking CCIP-BnM token from L2 into Eigenlayer example (with staker signatures)

## with associated Eigenlayer deposit events:



# https://ccip.chain.link/msg/0xb3f3972638bf9f52aa8629f9dd176acc597866b25b6f4a35a0c1d6ac06e2c850