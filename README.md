# L2 Eigenlayer Restaking

Scripts in the `scripts` folder:
- `5_depositWithSignatureFromArbToEth.sh` makes a cross-chain deposit into Eigenlayer from L2.
- `6_queueWithdrawalWithSignature.sh` queues a withdrawal from L2.
- `7_completeWithdrawalWithSignature.sh` completes the withdrawal and bridges the deposit back from L1 into the original staker's wallet on L2.
- You will need to re-run scripts `2_deployOnArb.s.sol`, `3_deployOnEth.s.sol` and `4_whitelistCCIPContracts.sh` if there are changes made to either the `SenderCCIP`, `ReceiverCCIP`, or `RestakingConnector` contracts.

Test run:
```
forge test -vvvv
```


## Sepolia L2 Restaking Flow

### 1. Deposit into Eigenlayer with a user signature

We bridge the token from L2 to L1, then deposit into Eigenlayer, with user signatures:
[https://ccip.chain.link/msg/0x5461125dca5718e09632cc40a7fc05c5d66a4a0e46e158445fed915549ecdbcf](https://ccip.chain.link/msg/0x5461125dca5718e09632cc40a7fc05c5d66a4a0e46e158445fed915549ecdbcf)

On L1, we can see the corresponding Eigenlayer deposit events:
[https://sepolia.etherscan.io/tx/0xf85b8b26f6c1873a19f5f6f5a3402e545e6d3fb7d641c37d5ef95dcc8275dae9](https://sepolia.etherscan.io/tx/0xf85b8b26f6c1873a19f5f6f5a3402e545e6d3fb7d641c37d5ef95dcc8275dae9)


### 2. Queue withdrawal from Eigenlayer with user signature

We then queue withdrawal from L2 with a user signature:
[https://ccip.chain.link/msg/0xc20f50990d8f84ca2f279ef87e80bc8e6951cdb8e37e5d10570bffd832007b17](https://ccip.chain.link/msg/0xc20f50990d8f84ca2f279ef87e80bc8e6951cdb8e37e5d10570bffd832007b17)

The message makes it's way to L1 resulting in the following Eigenlayer `queueWithdrawal` events:
[https://sepolia.etherscan.io/tx/0xafbcdff024c23fd76e5b1dd5ce90698639df3364e37a6dfda554cca92b9a89fd#eventlog](https://sepolia.etherscan.io/tx/0xafbcdff024c23fd76e5b1dd5ce90698639df3364e37a6dfda554cca92b9a89fd#eventlog)

Withdrawal events can be seen on DelegationManager contract on L1:
[https://sepolia.etherscan.io/address/0x6b78995ba97fb26de32ede9055d85f176b672af7#events](https://sepolia.etherscan.io/address/0x6b78995ba97fb26de32ede9055d85f176b672af7#events)

NOTE: we need to track the `block.number` of when this tx lands on L1, as it's used to form the withdrawalRoot you need to completeWithdrawals in the next step.
- add a `mapping(address => mapping(uint256 => uint256)) withdrawalBlock` to the ReceiverContract;
- then when we queueWithdrawal, we record `withdrawalBlock[staker][nonce] = block.number;`.
- then when we dispatch `completeWithdrawal()` later, we'll read from ReceiverContract.withdrawalBlock() to get the actual block number associated with the withdrawal.

Atm we store withdrawal information in `script/withdrawals-queued/<user_address>/` and `script/withdrawals-completed/<user_address>/`



### 3. Complete withdrawal from L2 and bridge back to original wallet on L2

We dispatch a call to complete the withdrawal to our SenderCCIP contract from L2:
[https://ccip.chain.link/msg/0x4417c1e8bd060ab8dd0276b86e4d5b8552488639c1bbc71ec3fce0079e484290](https://ccip.chain.link/msg/0x4417c1e8bd060ab8dd0276b86e4d5b8552488639c1bbc71ec3fce0079e484290)

Which executes on L1 with the following Eigenlayer completeWithdrawal events:
[https://sepolia.etherscan.io/tx/0x888f2c3b8b1faa9a5fdd6cc14d119ee39d1a8cc9f1c056335cf736edec891844](https://sepolia.etherscan.io/tx/0x888f2c3b8b1faa9a5fdd6cc14d119ee39d1a8cc9f1c056335cf736edec891844)


While the tokens are being bridged back, you can see the `messageId` in one of the emitted `Message Sent` event on the ReceiverCCIP contract:
[https://sepolia.etherscan.io/address/0xfccc6216301184b174dd4c7071415ce12ac4ce37#events](https://sepolia.etherscan.io/address/0xfccc6216301184b174dd4c7071415ce12ac4ce37#events)

Copy the `messageId` (topic[1]) on this page and search for it on `https://ccip.chain.link` to view  bridging status:
[https://ccip.chain.link/msg/0x827227a70b3efc72869847add23b9264b0fe05354cb0d6cc80ad15530657cf01](https://ccip.chain.link/msg/0x827227a70b3efc72869847add23b9264b0fe05354cb0d6cc80ad15530657cf01)

Once we wait for the L1 -> L2 bridge back, we can see the token transferred back to the original staker's account:
[https://sepolia.arbiscan.io/tx/0x7eceaf0d6c6fc55c994df20baad26b25a3a65b4d9601a31c39b29279903219c5](https://sepolia.arbiscan.io/tx/0x7eceaf0d6c6fc55c994df20baad26b25a3a65b4d9601a31c39b29279903219c5)



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
        - [ ] Add signatures on L1 receiver contract to verify staker's intent to completeWithdrawal on L1.
        - [ ] Add signatures on L2 sender contract and CCIP Message to verify tokens are transferred to the right staker address on L2.
        - [x] Alternatively, we can make a `mapping(bytes32 withdrawalRoot => Withdrawal)` mapping, then message the withdrawalRoot back to L2 instead of needing another user signature.  We look up the original staker on L2 when the L1 withdrawalRoot message arrives.
    - [ ] `delegate`
    - [ ] `undelegate`
- [ ] Refactor CCIP for messaging passing with no-token bridging option (currently sending 0.0001 tokens for withdrawals)

- Gas optimization
    - [ ] Estimate gas limit for each of the previous operations
    - [ ] CCIP offers manual execution in case of gas failures, need to look into this in case users get stuck transactions.

- [ ] Have Chainlink setups a Mock MAGIC "lane" for their CCIP bridge:
    - Chainlink CCIP only supports their own CCIP-BnM token in Sepolia testnet.
    - [ ] Can Chainlink deploy lanes on Holesky? Or can Eigenlayer deploy on Sepolia?

- Adapt differences in burn/mint model with CCIP-BnM and MAGIC's bridging model (Lock-and-mint?);