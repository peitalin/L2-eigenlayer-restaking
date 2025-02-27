#!/bin/bash

# Run tests in sequence to avoid API throttling
forge test --mp test/CCIP_ForkTest1_Deposit.t.sol
sleep(1)

forge test --mp test/CCIP_ForkTest2_QueueWithdrawal.t.sol
sleep(1)

forge test --mp test/CCIP_ForkTest3_CompleteWithdrawal.t.sol
sleep(1)

forge test --mp test/CCIP_ForkTest4_Delegation.t.sol
sleep(1)

forge test --mp test/CCIP_ForkTest4_Delegation.t.sol
sleep(1)

forge test --mp test/CCIP_ForkTest5_RewardsProcessClaim.t.sol
sleep(1)

forge test --mp test/ForkTests_BaseMessenger.t.sol

