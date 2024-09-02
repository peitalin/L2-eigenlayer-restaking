#!/bin/bash
source .env

echo forge script script/7_queueWithdrawal.s.sol:QueueWithdrawal --rpc-url basesepolia --broadcast -vvvv

forge script script/7_queueWithdrawal.s.sol:QueueWithdrawalScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv


# Users queue withdrawal via their 6551 EigenAgent from L2 with signatures:
# [https://ccip.chain.link/msg/0x2358f618e54c1b56510989002fc7da10691d9a8ecb99dce4c75a7446db193531](https://ccip.chain.link/msg/0x2358f618e54c1b56510989002fc7da10691d9a8ecb99dce4c75a7446db193531)


# The message routes to L1 creating `WithdrawalQueued` events in Eigenlayer's DelegationManager contract:
# [https://sepolia.etherscan.io/tx/0x5816ab72f39581e6b3f74ab90f29ff6e4382264ada642442e2bdd5208a23be3e#eventlog](https://sepolia.etherscan.io/tx/0x5816ab72f39581e6b3f74ab90f29ff6e4382264ada642442e2bdd5208a23be3e#eventlog)



