#!/bin/bash
source .env

echo forge script script/5_depositWithSignature.s.sol:DepositWithSignatureScript --rpc-url basesepolia --broadcast -vvvv

forge script script/5_depositWithSignature.s.sol:DepositWithSignatureScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv

## After running this script, search for the TX hash on https://ccip.chain.link/

## Example:
## Restaking CCIP-BnM token from L2 into Eigenlayer example (with staker signatures)
# https://ccip.chain.link/msg/0xab63cce8f46eb63aa3df280145e362a6eb2d0204b48f237fad493e094bb099e5

## with associated Eigenlayer deposit events:
# https://sepolia.etherscan.io/tx/0x1fdcc0cb12cb332cc704996f404f8d40d00c84166d3f5887c8e9e17ad370c374