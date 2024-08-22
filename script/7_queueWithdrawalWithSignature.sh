#!/bin/bash
source .env

echo forge script script/7_queueWithdrawalWithSignature.s.sol:QueueWithdrawalWithSignature --rpc-url basesepolia --broadcast -vvvv

forge script script/7_queueWithdrawalWithSignature.s.sol:QueueWithdrawalWithSignatureScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv



# https://ccip.chain.link/msg/0x003e44447eba1797ef07561bd3c391a490770a6383f8f0de3d0a19973b5e47f3