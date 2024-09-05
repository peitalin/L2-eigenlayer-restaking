# L2 Eigenlayer Restaking via ERC-6551 accounts




Eigenlayer does not allow ThirdParty withdrawals, users must use their wallets to deposit and withdraw funds. So we cannot withdraw on behalf of our users via L1 bridge contracts.

This forces us to either:
- **(Option 1)** force users to manually bridge to L1, deposit, withdraw, then bridge back to L2, or
- **(Option 2)** create an LRT for *every* operator.
- **(Option 4)** routing contract calls through user-owned 6551 accounts works around these issues, and keeps custody of funds with the user (who owns the 6551 NFT).



### Running L2 Restaking Scripts

Tests bridge from L2 to L1, then deposit in Eigenlayer, queueWithdrawal, completeWithdrawal, then bridge back to the original user on L2.

The scripts run on Base Sepolia, and Eth Sepolia and bridges CCIP's BnM ERC20 token (swap for MAGIC).

Test deposit and withdrawal:
```
forge test --match-test test_CCIP_Eigenlayer_CompleteWithdrawal -vvv
```
All Tests:
```
forge test -vvvv
```


To run the Scripts see the `scripts` folder:
- `5_depositWithSignature.sh`: makes a cross-chain deposit into Eigenlayer from L2.
- `6_queueWithdrawalWithSignature.sh`: queues a withdrawal from L2.
- `7_completeWithdrawal.sh`: completes the withdrawal and bridges the deposit back from L1 into the original staker's wallet on L2.

Scripts `2_deploySenderOnL2.s.sol`, `3_deployReceiverOnL1.s.sol` and `4_whitelistCCIPContracts.sh` deploy the CCIP bridge contracts, and 6551 and Eigenlayer Restaking handler contracts.

There are `2b` and `3b` upgrade scripts which need to be run when changes made to either the `SenderCCIP`, `ReceiverCCIP`,`RestakingConnector`, `SenderUtils`, `AgentFactory` or `EigenAgentOwner721` contracts.





## Sepolia L2 Restaking Flow

#### 1.  L2 Restaking into Eigenlayer via 6551 Agents (with signatures)

We bridge `0.00333` tokens from L2 to L1 first with a message to `DepositIntoStrategy`, signed by the user for their 6551 Agent to execute:
[User -> CCIP Bridge tx](https://ccip.chain.link/msg/0x08fb97248f1de5c23523591fc845e286013565dbf3344703c07279b7aa445310).

This then bridges across CCIP from L2 (Base Sepolia) to L1 (Eth Sepolia):
[CCIP -> L1](https://ccip.chain.link/msg/0x08fb97248f1de5c23523591fc845e286013565dbf3344703c07279b7aa445310)

On L1, we see the CCIP-BnM token routing through: [Sender CCIP (L1 Bridge) -> 6551 Agent -> Eigenlayer Strategy Vault](https://sepolia.etherscan.io/tx/0x929dc3f03eb10143d2a215cd0695348bca656ea026ed959b9cf449a0af79c2c4).

...with associated [6551 EigenAgent minting events](https://sepolia.etherscan.io/tx/0x929dc3f03eb10143d2a215cd0695348bca656ea026ed959b9cf449a0af79c2c4#eventlog#64).

...and `Deposit` events in the [Eigenlayer StrategyManager contract.](https://sepolia.etherscan.io/address/0x7d73d2641d4c68f7b8f11b1ce212645423a0e8b5#events).


Cost: 0.00195 ETH on Sepolia at 1.01 GWEI
(1,935,055 gas)

Assuming 5~10 GWEI on mainnet: 0.00967 ETH

See [Tenderly transaction for a full execution trace](https://dashboard.tenderly.co/tx/sepolia/0x929dc3f03eb10143d2a215cd0695348bca656ea026ed959b9cf449a0af79c2c4)



#### 2. Queue withdrawal via EigenAgent with user signature

Users queue withdrawal via their 6551 EigenAgent from L2 with signatures:
[]()


The message routes to L1 creating `WithdrawalQueued` events in Eigenlayer's DelegationManager contract:
[]()


Queued withdrawals information are stored in `script/withdrawals-queued/<user_address>/`, and completed withdrawals are stored in `script/withdrawals-completed/<user_address>/`.


NOTE:
EigenAgent accounts will only execute calls if the signature came from the user who owns the associated EigenAgentOwner 721 NFT.
See: [https://eips.ethereum.org/EIPS/eip-6551](https://eips.ethereum.org/EIPS/eip-6551)

Each user can only have 1 EigenAgentOwner NFT at the moment. We can make them tradeable or soulbound.

EigenAgent accounts are ERC1967 Proxies and can be upgraded. We can also look at BeaconProxy implementation if we want upgradeability for all accounts (Agents just route contract calls, so upgradeability is not strictly needed).

EigenAgentOwner NFTs are minted via the AgentFactory (which talks to a 6551 Registry and keeps track of EigenAgent 6551 accounts and ownership)
[]()

Cost of deploying EigenAgent should be manageable (as they use ERC1967 proxies (earlier versions used ERC1167 minimal proxies)):
```
forge test --match-test test_step5b_MintEigenAgent -vvvv --gas-report
```


#### 3. Complete withdrawal from L2 and bridge back to original wallet on L2

We dispatch a call to complete the withdrawal to our SenderCCIP contract from L2:
[]()

Which executes on L1 with the following Eigenlayer `WithdrawalCompleted` events:
[]()


The withdrawal is automatically bridged back with a L1 -> L2 CCIP message: you can see the `messageId` in one of the emitted `MessageSent` event on the ReceiverCCIP contract:
[messageId: E0D94E5E264424E2CBD8AE28F9CC7EFFCAE1EBB25424273561828F43944A9208]()

Copy the `messageId` (topic[1]) on this page and search for it on `https://ccip.chain.link` to view  bridging status:
[]()

Once the L1 -> L2 bridge completes, we can see the original `0.00333` tokens transferred back to the original staker's account:
[]()



### Comparing L2 Restaking Options

**Option 2 (Operator-specific LRTs)**
- Allows batching and potential gas savings for users, we'll need to subsidize gas for staking (which can get expensive)
- We take on more risk (we custody funds on behalf of operators in segregated LRT vaults)
- More friction starting an Operator: as we'll need to contract LRT operators to spin up new vaults. (not really permissionless)
- Need to build operator-specific dashboards, dev-ops processes for batch staking/unstaking, tracking withdrawals, and rewards accounting for each LRT operator (stuff Eigenlayer provides for native stakers).

**Option 4 (6551 Accounts for users)**
- Likely higher gas costs, but costs are paid by end-users (instead of us)
- Leverage existing dashboards from Eigenlayer (swap user address with EigenAgent address)
- No need to do withdrawals accounting, rewards accounting, or handle vaults
- More custom solidity code, need audits.



### TODO:
- [x] Deploy mock Eigenlayer contracts on Sepolia (Eigenlayer uses Holesky, but Chainlink are on Sepolia)
- [x] Deploy CCIP-BnM ERC20 strategy vault on Eigenlayer
- [ ] Test cross-chain messages for:
    - [x] `depositIntoStrategy` via EigenAgent
    - [x] `queueWithdrawals` via EigenAgent
    - [x] `completeQueuedWithdrawals` via EigenAgent
        - [x] Transfer withdrawn tokens from L1 back to L2
        - [x] Make `mapping(bytes32 withdrawalRoot => Withdrawal)` and `withdrawalRootsSpent` mappings on the L2 SenderCCIP bridge, so that when the `withdrawalRoot` is messaged back from L1 we can look up the original staker on L2 to transfer to without needing another signature.
    - [x] `delegateTo`
    - [x] `undelegate` (this also withdraws the staker and has the same constraints as queueWithdrawals). There is no way to directly re-delegate to another operator, a staker must undelegate + withdraw, wait 7 days, then restake and re-delegate to a new operator.

- Gas optimization
    - [x] Estimate gas limit for each of the previous operations
    - [x] Reduce gas costs associated with 6551 accounts creation + delegate calls
    - [ ] CCIP offers manual execution in case of gas failures, need to look into this in case users get stuck transactions.

- [ ] Have Chainlink setups a Mock MAGIC "lane" for their CCIP bridge:
    - Chainlink CCIP only supports their own CCIP-BnM token in Sepolia testnet.
    - [ ] Can Chainlink deploy lanes on Holesky? Or can Eigenlayer deploy on Sepolia?

- Adapt differences in burn/mint model with CCIP-BnM and MAGIC's bridging model (Lock-and-mint?);




### Example 2:

#### 1. CCIP Mint EigenAgent and Deposit message from L2:
[https://ccip.chain.link/msg/0x08fb97248f1de5c23523591fc845e286013565dbf3344703c07279b7aa445310](https://ccip.chain.link/msg/0x08fb97248f1de5c23523591fc845e286013565dbf3344703c07279b7aa445310)

...with associated `Deposit` and 6551 EigenAgent minting events:
[https://sepolia.etherscan.io/tx/0x929dc3f03eb10143d2a215cd0695348bca656ea026ed959b9cf449a0af79c2c4](https://sepolia.etherscan.io/tx/0x929dc3f03eb10143d2a215cd0695348bca656ea026ed959b9cf449a0af79c2c4)

Cost: 0.00195 ETH on Sepolia at 1.01 GWEI
(1,935,055 gas)

Assuming 5~10 GWEI on mainnet: 0.00967 ETH

See [Tenderly transaction for a full execution trace](https://dashboard.tenderly.co/tx/sepolia/0x929dc3f03eb10143d2a215cd0695348bca656ea026ed959b9cf449a0af79c2c4)

#### 2. CCIP queueWithdrawal message from L2:
[https://ccip.chain.link/msg/0x9d0316418adbcf5b421ed7f88db9533cd31f88dbc9eb3bcaffb26f36b6bd0724](https://ccip.chain.link/msg/0x9d0316418adbcf5b421ed7f88db9533cd31f88dbc9eb3bcaffb26f36b6bd0724)

...with associated `WithdrawalQueued` event:
[https://sepolia.etherscan.io/tx/0x47cf673a884cd188f516eeb60521485999d5bade79382d9f1c02e7850d869870#eventlog#33](https://sepolia.etherscan.io/tx/0x47cf673a884cd188f516eeb60521485999d5bade79382d9f1c02e7850d869870#eventlog#33)


#### 3. CCIP completeWithdrawal message from L2:
[https://ccip.chain.link/msg/0x08a17dc0a3a75706cb5ad7e3102c21a889731b66c2f4e669989a0e9c3d46f01f](https://ccip.chain.link/msg/0x08a17dc0a3a75706cb5ad7e3102c21a889731b66c2f4e669989a0e9c3d46f01f)

...with associated `WithdrawalCompleted` event:
[https://sepolia.etherscan.io/tx/0x89acac38101ef9710c3eed544efb5acffc13b710cd4959c24f9a1008c6dd2509#eventlog#2](https://sepolia.etherscan.io/tx/0x89acac38101ef9710c3eed544efb5acffc13b710cd4959c24f9a1008c6dd2509#eventlog#2)

The L2 Bridge contract will automatically dispatch a message to return the withdrawal to L2.
You can see the `messageId` here in `topic[1]`:
[https://sepolia.etherscan.io/tx/0x89acac38101ef9710c3eed544efb5acffc13b710cd4959c24f9a1008c6dd2509#eventlog#16](https://sepolia.etherscan.io/tx/0x89acac38101ef9710c3eed544efb5acffc13b710cd4959c24f9a1008c6dd2509#eventlog#16)


#### 4. CCIP message (and CCIP messageID) to bridge withdrawn funds back to L1:

Copy and paste the `messageId` back into the CCIP explorer to track the L1 -> L2 transaction:
[https://ccip.chain.link/msg/0xcfa18eac0bf18e93620cf4a51a015485b42a6ba82025e1e7562b3405cc592856](https://ccip.chain.link/msg/0xcfa18eac0bf18e93620cf4a51a015485b42a6ba82025e1e7562b3405cc592856)

When the withdrawn funds arrive on L2, they are transferred back to the original user's address:
[https://sepolia.basescan.org/tx/0x8e19a09c3e8d8a56bff89c4a54221cecc8f78bada6e2db4164198c4f7cc3f1a5](https://sepolia.basescan.org/tx/0x8e19a09c3e8d8a56bff89c4a54221cecc8f78bada6e2db4164198c4f7cc3f1a5)



#### 5a. DelegateTo

[Successful delegateTo call](https://ccip.chain.link/msg/0x241da6f1da5d9a8262c6767486a0134de9e12db1ac3d49e4f8e8ff364c7b6236)

#### 5b. Undelegate

Undelegating also cues the staker for withdrawal and produces withdrawalRoots.

You can either:
(1) completeWithdrawals and receive your withdrawal as tokens, or
(2) completeWithdrawals and receive your withdrawal as shares in the vault (which can be re-delegated)

The `receiveAsTokens` flag in `completeWithdrawals` call determines this.

[Undelegate call](https://ccip.chain.link/msg/0xd47a04c1d4aa55082e3471669673e07b78475fe870c555075defeecb1b6f581e)


#### 5c. Re-deposit (after re-delegating)

[Redeposit Message](https://ccip.chain.link/msg/0x3857a387fdcd0d87a1f7c48ac7cdfc26c19cf21ec2b069acf4d67d93e9d94cd7)