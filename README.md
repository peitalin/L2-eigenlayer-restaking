## L2 Eigenlayer Restaking

Run the scripts in the `scripts` folder (they are numbered):
- Skip script `1_deployMockEigenlayerContracts.sh` as Eigenlayer is already deployed on ETH Sepolia.
- You can try `5_depositWithSignatureFromArbToEth.sh` to make a x-chain deposit into Eigenlayer.
- You will need to re-run scripts 2 and 3 if you make changes to either the SenderCCIP, ReceiverCCIP, or RestakingConnector contracts.

Run:
```
forge test -vvv
```


TODO:
- [x] deploy mock Eigenlayer contracts on Sepolia (Eigenlayer uses Holesky, but Chainlink are on Sepolia)
- [x] deploy CCIP-BnM ERC20 strategy vault on Eigenlayer
- Test cross-chain messages for:
    - [x] `depositIntoStrategy`
    - [x] `depositIntoStrategyWithSignature` (EIP1271 signatures to attribute deposits to stakers on L2)
    - [x] `queueWithdrawals`
    - [x] `queueWithdrawalsWithSignature` ([requires PR #646 to work](https://github.com/Layr-Labs/eigenlayer-contracts/pull/676/files))
    - [x] `completeQueuedWithdrawals`
        - [x] Transfer withdrawn tokens from L1 back to L2
        - [ ] Add signatures on L1 receiver contract to verify staker's intent to completeWithdrawal on L1.
        - [ ] Add signatures on L2 sender contract and CCIP Message to verify tokens are transferred to the right staker address on L2.
    - [ ] `delegate`
    - [ ] `undelegate`
- Gas
    - estimate gas limit for each of the previous operations
    - CCIP offers manual execution in case of gas failures, need to look into this.

- Swap CCIP's BnM ERC20 with Mock MAGIC:
    - We will need Chainlink to add a MockMAGIC CCIP Lane:
    - Chainlink CCIP only supports their own CCIP-BnM token in testnet.
    - adapt differences in burn/mint model with CCIP-BnM and MAGIC's bridging model (Lock-and-mint?);