#!/bin/bash
source .env

echo forge script script/7_completeWithdrawalWithSignature.s.sol:CompleteWithdrawalWithSignature --rpc-url arbsepolia --broadcast -vvvv

forge script script/7_completeWithdrawalWithSignature.s.sol:CompleteWithdrawalWithSignatureScript  \
    --rpc-url arbsepolia \
    --broadcast \
    -vvvv

## After running this script, search for the TX hash on https://ccip.chain.link/
## On testnet, it can take ~30min for Chainlink to bridge.

## Example:
## Complete Withdrawal from L2 (with signatures)
# https://ccip.chain.link/msg/0x2051e290ad0c5387d240eb5be450aff6bf863131783f14f630016be2e4a83658

## with associated Eigenlayer queueWithdrawal events:
