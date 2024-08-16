#!/bin/bash
source .env

echo forge script script/6_queueWithdrawalWithSignature.s.sol:QueueWithdrawalWithSignature --rpc-url arbsepolia --broadcast -vvvv

forge script script/6_queueWithdrawalWithSignature.s.sol:QueueWithdrawalWithSignatureScript  \
    --rpc-url arbsepolia \
    --broadcast \
    -vvvv


