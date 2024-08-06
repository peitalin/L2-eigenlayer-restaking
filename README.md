## L2 Eigenlayer Restaking

TODO:
- [DONE] deploy mock Eigenlayer contracts on Sepolia (Eigenlayer uses Holesky, but Chainlink are on Sepolia)
- [DONE] deploy CCIP-BnM ERC20 strategy vault on Eigenlayer
- Test cross-chain messages for:
    - [DONE] `depositIntoStrategy`
    - `depositIntoStrategyWithSignature` (EIP1271 signatures to attribute deposits to stakers on L2)
    - `queueWithdrawals`
    - `completeQueuedWithdrawals`
    - `delegate`
    - `undelegate`
- Gas
    - estimate gas limit for each of the previous operations
    - CCIP offers manual execution in case of gas failures, need to look into this.

- Swap CCIP's BnM ERC20 with Mock MAGIC:
    - We will need Chainlink to add a MockMAGIC CCIP Lane:
    - Chainlink CCIP only supports their own CCIP-BnM token in testnet.
    - adapt differences in burn/mint model with CCIP-BnM and MAGIC's bridging model (Lock-and-mint?);