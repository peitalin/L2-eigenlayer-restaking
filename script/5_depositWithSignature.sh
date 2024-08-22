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



# https://ccip.chain.link/msg/0xab63cce8f46eb63aa3df280145e362a6eb2d0204b48f237fad493e094bb099e5
# https://sepolia.etherscan.io/tx/0x1fdcc0cb12cb332cc704996f404f8d40d00c84166d3f5887c8e9e17ad370c374