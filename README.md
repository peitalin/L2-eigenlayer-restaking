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
[https://sepolia.basescan.org/tx/0xafc1cf7a6629a53b525c49e3637d6f5accb8021a3a08a9e253ffd5f5a25876da](https://sepolia.basescan.org/tx/0xafc1cf7a6629a53b525c49e3637d6f5accb8021a3a08a9e253ffd5f5a25876da)

This then bridges across CCIP from L2 (Base Sepolia) to L1 (Eth Sepolia):
[https://ccip.chain.link/msg/0x025b854ed6d4c0af1b2c8cf696fb3f310702492cdbe2618135dacf4d74208e2b](https://ccip.chain.link/msg/0x025b854ed6d4c0af1b2c8cf696fb3f310702492cdbe2618135dacf4d74208e2b)

On L1, we see the CCIP-BnM token routing through: Sender CCIP (L1 Bridge) -> 6551 Agent -> Eigenlayer Strategy Vault:
[https://sepolia.etherscan.io/tx/0x55580c6681525f385198639814f1e54e9213c613cdcdef806e89e9403f3f3c9a](https://sepolia.etherscan.io/tx/0x55580c6681525f385198639814f1e54e9213c613cdcdef806e89e9403f3f3c9a)

...which we also see in the Eigenlayer StrategyManager contract: [https://sepolia.etherscan.io/address/0x7d73d2641d4c68f7b8f11b1ce212645423a0e8b5#events](https://sepolia.etherscan.io/address/0x7d73d2641d4c68f7b8f11b1ce212645423a0e8b5#events)


TODO: Gas cost estimates in (i) bridging, (ii) creating a 6551 EigenAgent, (iii) depositing in Eigenalayer


#### 2. Queue withdrawal via EigenAgent with user signature

Users queue withdrawal via their 6551 EigenAgent from L2 with signatures:
[https://ccip.chain.link/msg/0x2358f618e54c1b56510989002fc7da10691d9a8ecb99dce4c75a7446db193531](https://ccip.chain.link/msg/0x2358f618e54c1b56510989002fc7da10691d9a8ecb99dce4c75a7446db193531)


The message routes to L1 creating `WithdrawalQueued` events in Eigenlayer's DelegationManager contract:
[https://sepolia.etherscan.io/tx/0x5816ab72f39581e6b3f74ab90f29ff6e4382264ada642442e2bdd5208a23be3e#eventlog](https://sepolia.etherscan.io/tx/0x5816ab72f39581e6b3f74ab90f29ff6e4382264ada642442e2bdd5208a23be3e#eventlog)


Queued withdrawals information are stored in `script/withdrawals-queued/<user_address>/`, and completed withdrawals are stored in `script/withdrawals-completed/<user_address>/`.


NOTE:
EigenAgent accounts will only execute calls if the signature came from the user who owns the associated EigenAgentOwner 721 NFT.
See: [https://eips.ethereum.org/EIPS/eip-6551](https://eips.ethereum.org/EIPS/eip-6551)

Each user can only have 1 EigenAgentOwner NFT at the moment. We can make them tradeable or soulbound.

EigenAgent accounts are ERC1967 Proxies and can be upgraded. We can also look at BeaconProxy implementation if we want upgradeability for all accounts (Agents just route contract calls, so upgradeability is not strictly needed).

EigenAgentOwner NFTs are minted via the AgentFactory (which talks to a 6551 Registry and keeps track of EigenAgent 6551 accounts and ownership)
[https://sepolia.etherscan.io/address/0x551c6f21ba8c842ed58c2124a07766e903f24c75#internaltx](https://sepolia.etherscan.io/address/0x551c6f21ba8c842ed58c2124a07766e903f24c75#internaltx)

Cost of deploying EigenAgent should be manageable (as they use ERC1967 proxies (earlier versions used ERC1167 minimal proxies)):
```
forge test --match-test test_step5b_MintEigenAgent -vvvv --gas-report
```


#### 3. Complete withdrawal from L2 and bridge back to original wallet on L2

We dispatch a call to complete the withdrawal to our SenderCCIP contract from L2:
[https://ccip.chain.link/msg/0x2bf12fb2f940fb2b3258e1c05d76bd0cdee91c95a34058e1439f152d31dfccb7](https://ccip.chain.link/msg/0x2bf12fb2f940fb2b3258e1c05d76bd0cdee91c95a34058e1439f152d31dfccb7)

Which executes on L1 with the following Eigenlayer `WithdrawalCompleted` events:
[https://sepolia.etherscan.io/tx/0x3a55a8ed9bd23c1b2bec5f24be4c7c71da9a21ab2e2f39ba51c5835811df153b#eventlog](https://sepolia.etherscan.io/tx/0x3a55a8ed9bd23c1b2bec5f24be4c7c71da9a21ab2e2f39ba51c5835811df153b#eventlog)


The withdrawal is automatically bridged back with a L1 -> L2 CCIP message: you can see the `messageId` in one of the emitted `MessageSent` event on the ReceiverCCIP contract:
[messageId: E0D94E5E264424E2CBD8AE28F9CC7EFFCAE1EBB25424273561828F43944A9208](https://sepolia.etherscan.io/tx/0x3a55a8ed9bd23c1b2bec5f24be4c7c71da9a21ab2e2f39ba51c5835811df153b#eventlog#144)

Copy the `messageId` (topic[1]) on this page and search for it on `https://ccip.chain.link` to view  bridging status:
[https://ccip.chain.link/msg/0xe0d94e5e264424e2cbd8ae28f9cc7effcae1ebb25424273561828f43944a9208](https://ccip.chain.link/msg/0xe0d94e5e264424e2cbd8ae28f9cc7effcae1ebb25424273561828f43944a9208)

Once the L1 -> L2 bridge completes, we can see the original `0.00333` tokens transferred back to the original staker's account:
[https://sepolia.basescan.org/tx/0x1753d98c605f9fc542e1a612531c634afd6da647b2eb4f1d6d094f74af94e9a8](https://sepolia.basescan.org/tx/0x1753d98c605f9fc542e1a612531c634afd6da647b2eb4f1d6d094f74af94e9a8)



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
    - [ ] `delegateTo`
    - [ ] `undelegate` (this also withdraws the staker and has the same constraints as queueWithdrawals). There is no way to directly re-delegate to another operator, a staker must undelegate + withdraw, wait 7 days, then restake and re-delegate to a new operator.

- Gas optimization
    - [ ] Estimate gas limit for each of the previous operations
    - [ ] Reduce gas costs associated with 6551 accounts creation + delegate calls
    - [ ] CCIP offers manual execution in case of gas failures, need to look into this in case users get stuck transactions.

- [ ] Have Chainlink setups a Mock MAGIC "lane" for their CCIP bridge:
    - Chainlink CCIP only supports their own CCIP-BnM token in Sepolia testnet.
    - [ ] Can Chainlink deploy lanes on Holesky? Or can Eigenlayer deploy on Sepolia?

- Adapt differences in burn/mint model with CCIP-BnM and MAGIC's bridging model (Lock-and-mint?);




### Example 2 (with a non-deployer account):

#### 1. CCIP Mint EigenAgent and Deposit message from L2:
[https://ccip.chain.link/msg/0xa6a95f12fed2e29ca8e74ceca711f18746853cb087d07c51b3b31cd77b2bbd18](https://ccip.chain.link/msg/0xa6a95f12fed2e29ca8e74ceca711f18746853cb087d07c51b3b31cd77b2bbd18)

...with assocaited `Deposit` event:
[https://sepolia.etherscan.io/tx/0xf2e146800acedcc8fd366bc3668add33c5ac748b4eab893095470036170626b5]
(https://sepolia.etherscan.io/tx/0xf2e146800acedcc8fd366bc3668add33c5ac748b4eab893095470036170626b5)


#### 2. CCIP queueWithdrawal message from L2:
[https://ccip.chain.link/msg/0x3644dee9d68d2340f4b835280dfe5136bfc94ad5e42aa31af5a49c26ce3de98e]
(https://ccip.chain.link/msg/0x3644dee9d68d2340f4b835280dfe5136bfc94ad5e42aa31af5a49c26ce3de98e)

...with associated `WithdrawalQueued` event:
[https://sepolia.etherscan.io/tx/0x10cf29842862daee469ce39aaa57b166fe5fe6662dc1a9f113536eb98de411f4#eventlog#60](https://sepolia.etherscan.io/tx/0x10cf29842862daee469ce39aaa57b166fe5fe6662dc1a9f113536eb98de411f4#eventlog#60)


#### 3. CCIP completeWithdrawal message from L2:
[https://ccip.chain.link/msg/0xca947ff0dc61aafed61f54efc627c767390f1cfb114fed4761a3e80e55c7f498]
(https://ccip.chain.link/msg/0xca947ff0dc61aafed61f54efc627c767390f1cfb114fed4761a3e80e55c7f498)

...with associated `WithdrawalCompleted` event:
[https://sepolia.etherscan.io/tx/0xac83846d482e7a92f13bd39024b67b3fc94311f83e10a8d8a2c32434189e7298#eventlog#35](https://sepolia.etherscan.io/tx/0xac83846d482e7a92f13bd39024b67b3fc94311f83e10a8d8a2c32434189e7298#eventlog#35)

The L2 Bridge contract will automatically dispatch a message to return the withdrawal to L2:
[https://sepolia.etherscan.io/tx/0xac83846d482e7a92f13bd39024b67b3fc94311f83e10a8d8a2c32434189e7298#eventlog#50](https://sepolia.etherscan.io/tx/0xac83846d482e7a92f13bd39024b67b3fc94311f83e10a8d8a2c32434189e7298#eventlog#50)


#### 4. CCIP message (and CCIP messageID) to bridge withdrawn funds back to L1:

...Which you can you can track the L1 -> L2 brige back on CCIP:
[https://ccip.chain.link/msg/0x5b3f6bf4cd50d4d9f335cee7072278acfe536e94689fdfc62c4bf7a3e6b1684b]
(https://ccip.chain.link/msg/0x5b3f6bf4cd50d4d9f335cee7072278acfe536e94689fdfc62c4bf7a3e6b1684b)


When the withdrawn funds arrive on L2, they are transferred back to the original user's address:
[https://sepolia.basescan.org/tx/0x53961a97e21df2080ae8cd75a284fdff4b99e701c2744e5eea3bb0ca2042ad27](https://sepolia.basescan.org/tx/0x53961a97e21df2080ae8cd75a284fdff4b99e701c2744e5eea3bb0ca2042ad27)
