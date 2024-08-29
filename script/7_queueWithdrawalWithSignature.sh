#!/bin/bash
source .env

echo forge script script/7_queueWithdrawalWithSignature.s.sol:QueueWithdrawalWithSignature --rpc-url basesepolia --broadcast -vvvv

forge script script/7_queueWithdrawalWithSignature.s.sol:QueueWithdrawalWithSignatureScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv


# Users queue withdrawal via their 6551 EigenAgent from L2 with signatures:
# [https://ccip.chain.link/msg/0xa5fb65eff93c716bfad205dcaa0225737fc665e53bee55fb23db07ac5b499018](https://ccip.chain.link/msg/0xa5fb65eff93c716bfad205dcaa0225737fc665e53bee55fb23db07ac5b499018)


# The message makes it's way to L1 resulting in the following Eigenlayer `queueWithdrawal` events:
# [https://sepolia.etherscan.io/tx/0x21b1e008d4fdf5a5a966f0bd65bbb13a1a4187a242a7f7c7ab8fb4c86410b1d7](https://sepolia.etherscan.io/tx/0x21b1e008d4fdf5a5a966f0bd65bbb13a1a4187a242a7f7c7ab8fb4c86410b1d7)

# Withdrawal events can be seen on DelegationManager contract on L1:
# [https://sepolia.etherscan.io/address/0xebbc61ccacf45396ff4b447f353cea404993de98#events](https://sepolia.etherscan.io/address/0xebbc61ccacf45396ff4b447f353cea404993de98#events)
