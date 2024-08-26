# L2 Eigenlayer Restaking

Scripts in the `scripts` folder:
- `5_depositWithSignatureFromArbToEth.sh` makes a cross-chain deposit into Eigenlayer from L2.
- `6_queueWithdrawalWithSignature.sh` queues a withdrawal from L2.
- `7_completeWithdrawalWithSignature.sh` completes the withdrawal and bridges the deposit back from L1 into the original staker's wallet on L2.
- You will need to re-run scripts `2_deploySenderOnL2.s.sol`, `3_deployReceiverOnL1.s.sol` and `4_whitelistCCIPContracts.sh` if there are changes made to either the `SenderCCIP`, `ReceiverCCIP`, or `RestakingConnector` contracts.

Test run:
```
forge test -vvvv
```


## Sepolia L2 Restaking Flow

### 1. Deposit into Eigenlayer with a user signature

We bridge the token from L2 to L1, then deposit into Eigenlayer, with user signatures:
[https://ccip.chain.link/msg/0xab63cce8f46eb63aa3df280145e362a6eb2d0204b48f237fad493e094bb099e5](https://ccip.chain.link/msg/0xab63cce8f46eb63aa3df280145e362a6eb2d0204b48f237fad493e094bb099e5)

On L1, we can see the corresponding Eigenlayer deposit events in the ReceiverCCIP bridge contract:
[https://sepolia.etherscan.io/tx/0x1fdcc0cb12cb332cc704996f404f8d40d00c84166d3f5887c8e9e17ad370c374#eventlog](https://sepolia.etherscan.io/tx/0x1fdcc0cb12cb332cc704996f404f8d40d00c84166d3f5887c8e9e17ad370c374#eventlog)

and also in the Eigenlayer StrategyManager contract: [https://sepolia.etherscan.io/address/0x7d73d2641d4c68f7b8f11b1ce212645423a0e8b5#events](https://sepolia.etherscan.io/address/0x7d73d2641d4c68f7b8f11b1ce212645423a0e8b5#events)


### 2. Queue withdrawal from Eigenlayer with user signature

We then queue withdrawal from L2 with a user signature:
[https://ccip.chain.link/msg/0x003e44447eba1797ef07561bd3c391a490770a6383f8f0de3d0a19973b5e47f3](https://ccip.chain.link/msg/0x003e44447eba1797ef07561bd3c391a490770a6383f8f0de3d0a19973b5e47f3)

The message makes it's way to L1 resulting in the following Eigenlayer `queueWithdrawal` events:
[https://sepolia.etherscan.io/tx/0xc2c04b4bfbc12c2f6591aef31bf7825cde941835ca555e28fa23f9336ec804a3#eventlog](https://sepolia.etherscan.io/tx/0xc2c04b4bfbc12c2f6591aef31bf7825cde941835ca555e28fa23f9336ec804a3#eventlog)

Withdrawal events can be seen on DelegationManager contract on L1:
[https://sepolia.etherscan.io/address/0xebbc61ccacf45396ff4b447f353cea404993de98#events](https://sepolia.etherscan.io/address/0xebbc61ccacf45396ff4b447f353cea404993de98#events)



### 3. Complete withdrawal from L2 and bridge back to original wallet on L2

We dispatch a call to complete the withdrawal to our SenderCCIP contract from L2:
[https://ccip.chain.link/msg/0x3a02206482f0148c74cb4b34a631b998502c754d198abc378e10ccaf6c725825](https://ccip.chain.link/msg/0x3a02206482f0148c74cb4b34a631b998502c754d198abc378e10ccaf6c725825)

Which executes on L1 with the following Eigenlayer completeWithdrawal events:
[https://sepolia.etherscan.io/tx/0xc4e336ee410598fff9e6951b176b11e4ac6f3d0df2768eb79a986ada7e829037#eventlog](https://sepolia.etherscan.io/tx/0xc4e336ee410598fff9e6951b176b11e4ac6f3d0df2768eb79a986ada7e829037#eventlog)


While the tokens are being bridged back, you can see the `messageId` in one of the emitted `Message Sent` event on the ReceiverCCIP contract:
[https://sepolia.etherscan.io/address/0x4c854b17250582413783b96e020e5606a561eddc#events](https://sepolia.etherscan.io/address/0x4c854b17250582413783b96e020e5606a561eddc#events)

Copy the `messageId` (topic[1]) on this page and search for it on `https://ccip.chain.link` to view  bridging status:
[https://ccip.chain.link/msg/0xf6165cfb76cceaebbb93e9b49f7ac373547e51368bf9048c59c90c2d774fc42e](https://ccip.chain.link/msg/0xf6165cfb76cceaebbb93e9b49f7ac373547e51368bf9048c59c90c2d774fc42e)

Once we wait for the L1 -> L2 bridge back, we can see the token transferred back to the original staker's account:
[https://sepolia.basescan.org/tx/0xf4824d3fc1925a91f5cec814d6e03985092c38e7838c38f83d755a698923446c](https://sepolia.basescan.org/tx/0xf4824d3fc1925a91f5cec814d6e03985092c38e7838c38f83d755a698923446c)



## TODO:
- [x] Deploy mock Eigenlayer contracts on Sepolia (Eigenlayer uses Holesky, but Chainlink are on Sepolia)
- [x] Deploy CCIP-BnM ERC20 strategy vault on Eigenlayer
- [ ] Test cross-chain messages for:
    - [x] `depositIntoStrategy`
    - [x] `depositIntoStrategyWithSignature` (EIP1271 signatures to attribute deposits to stakers on L2)
    - [x] `queueWithdrawals`
    - [x] `queueWithdrawalsWithSignature` ([requires PR #646 to work](https://github.com/Layr-Labs/eigenlayer-contracts/pull/676/files))
    - [x] `completeQueuedWithdrawals`
        - [x] Transfer withdrawn tokens from L1 back to L2
        - [x] Make `mapping(bytes32 withdrawalRoot => Withdrawal)` and `withdrawalRootsSpent` mappings on L1 SenderCCIP bridge, so when the withdrawalRoot is messaged back from L1 we can look up the original staker on L2 to transfer to without needing another signature.
        - [x] Add `setQueueWithdrawalBlock(staker, nonce)` and `getQueueWithdrawalBlock(staker, nonce)` to record the `block.number` needed to re-created the withdrawalRoot to `completeQueuedWithdrawal` via L2.
Queued withdrawals are store in `script/withdrawals-queued/<user_address>/`, and completed withdrawals are recored in `script/withdrawals-completed/<user_address>/`.
    - [x] Refactor CCIP for messaging passing with no-token bridging option
    - [x] `delegateToBySignature`
    - [ ] `undelegate` (this also withdraws the staker, so we will probably need a `undelegateWithSignature` feature as well from Eigenlayer). There is no way to directly re-delegate to another operator, a staker must undelegate + withdraw, wait 7 days, then restake and re-delegate to a new operator.

- Gas optimization
    - [ ] Estimate gas limit for each of the previous operations
    - [ ] CCIP offers manual execution in case of gas failures, need to look into this in case users get stuck transactions.

- [ ] Have Chainlink setups a Mock MAGIC "lane" for their CCIP bridge:
    - Chainlink CCIP only supports their own CCIP-BnM token in Sepolia testnet.
    - [ ] Can Chainlink deploy lanes on Holesky? Or can Eigenlayer deploy on Sepolia?

- Adapt differences in burn/mint model with CCIP-BnM and MAGIC's bridging model (Lock-and-mint?);