#!/bin/bash
source .env

echo forge script script/6_queueWithdrawalWithSignature.s.sol:QueueWithdrawalWithSignature --rpc-url arbsepolia --broadcast -vvvv

forge script script/6_queueWithdrawalWithSignature.s.sol:QueueWithdrawalWithSignatureScript  \
    --rpc-url arbsepolia \
    --broadcast \
    -vvvv

## After running this script, search for the TX hash on https://ccip.chain.link/
## On testnet, it can take ~30min for Chainlink to bridge.

## Example:
## Queue Withdrawal from L2 (with signatures)
# https://ccip.chain.link/msg/0x8239f2b49ab2b36611fec60e4f2cf99bc460b4d413f8627f964263a4beea394c

## with associated Eigenlayer queueWithdrawal events:
# https://sepolia.etherscan.io/tx/0x20baf6809a2dc7120f4ad81b1df6c1e876b47cc6deb88800ef538d1cb3803bf2#eventlog

## and withdrawal event on DelegationManager contract on L1:
# https://sepolia.etherscan.io/address/0x6b78995ba97fb26de32ede9055d85f176b672af7#events