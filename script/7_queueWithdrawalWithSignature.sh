#!/bin/bash
source .env

echo forge script script/7_queueWithdrawalWithSignature.s.sol:QueueWithdrawalWithSignature --rpc-url basesepolia --broadcast -vvvv

forge script script/7_queueWithdrawalWithSignature.s.sol:QueueWithdrawalWithSignatureScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv



# https://ccip.chain.link/msg/0x24f0d024d70365a86229b3c1d5c6b74587a8a583588e1dcc1786c2549ed7050b

# https://sepolia.etherscan.io/tx/0xafd0ea60a872ae7eddca424e9c4bb180e5b0c3b4a0696ac9fdd3e238864ed040#eventlog