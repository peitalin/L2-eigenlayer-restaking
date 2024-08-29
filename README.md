# L2 Eigenlayer Restaking via 6551 accounts


#### Comparing L2 Restaking Options

Eigenlayer does not allow ThirdParty withdrawals, users must use their wallets to deposit and withdraw funds, so you cannot stake/withdraw for users from our L1 bridge contracts and L2 restaking is impossible.

This forces us to either (1) force users to manually bridge to L1, stake, withdraw, then bridge back to L2, or (2) create an LRT for *every* operator.

Routing contract calls from L2 through user-owned 6551 Accounts works around these issues, and keeps custody of funds with the user (who owns the 6551 NFT).

*Option 2 (Operator-specific LRTs)*
- Allows batching and potential gas savings for users, we'll need to subsidize gas for staking (which can get expensive)
- We take on more risk (we custody funds on behalf of operators in segregated LRT vaults)
- More friction starting an Operator: as we'll need to contract LRT operators to spin up new vaults. (not really permissionless)
- Need to build operator-specific dashboards, dev-ops processes for batch staking/unstaking, tracking withdrawals, and rewards accounting for each LRT operator (stuff Eigenlayer provides for native stakers).

*Option 4 (6551 Accounts for users)*
- Likely higher gas costs, but costs are paid by end-users (instead of us)
- Leverage existing dashboards from Eigenlayer (swap user address with EigenAgent address)
- no need to do withdrawals accounting, rewards accounting, handle vaults
- Custom solidity code, need audits.



#### Running L2 Restaking Scripts

Tests bridge from L2 to L1, then deposit in Eigenlayer, queueWithdrawal, completeWithdrawal, then bridge back to the original user on L2.

The scripts run on Base Sepolia, and Eth Sepolia and bridges CCIP's BnM ERC20 token (swap for MAGIC).

Tests:
```
forge test --match-test test_CCIP_Eigenlayer_CompleteWithdrawal -vvv
```
```
forge test -vvv
```


To run the Scripts see the `scripts` folder:
- `5_depositWithSignature.sh`: makes a cross-chain deposit into Eigenlayer from L2.
- `6_queueWithdrawalWithSignature.sh`: queues a withdrawal from L2.
- `7_completeWithdrawal.sh`: completes the withdrawal and bridges the deposit back from L1 into the original staker's wallet on L2.

Scripts `2_deploySenderOnL2.s.sol`, `3_deployReceiverOnL1.s.sol` and `4_whitelistCCIPContracts.sh` deploy the CCIP bridge contracts, and 6551 and Eigenlayer Restaking handler contracts.

There are `2b` and `3b` upgrade scripts which need to be run when changes made to either the `SenderCCIP`, `ReceiverCCIP`,`RestakingConnector`, `SenderUtils`, `AgentFactory` or `EigenAgentOwner721` contracts.





## Sepolia L2 Restaking Flow

#### 1.  L2 Restaking into Eigenlayer via 6551 Agents (with signatures)

We bridge the token from L2 to L1, then deposit into Eigenlayer through 6551 accounts owned by the user, with user signatures:
[https://ccip.chain.link/msg/0x8a985c00bfafce4fb3e52f281ec5d1bfd4e15c82333f27cc2fd5064422b1f10b](https://ccip.chain.link/msg/0x8a985c00bfafce4fb3e52f281ec5d1bfd4e15c82333f27cc2fd5064422b1f10b)

On L1, we see the CCIP-BnM token routing through: Sender CCIP (L1 Bridge) -> 6551 Agent -> Eigenlayer Strategy Vault:
[https://sepolia.etherscan.io/tx/0x90fb208ac0596b3c407d50bbbcd78b074ac459e53248b551cbe56fa16c0a302a](https://sepolia.etherscan.io/tx/0x90fb208ac0596b3c407d50bbbcd78b074ac459e53248b551cbe56fa16c0a302a)

Gas cost: 0.01396 ETH (approx $36) in (i) bridging, (ii) creating a 6551 EigenAgent, (iii) depositing in Eigenalayer

Deposit events can be seen in the Eigenlayer StrategyManager contract: [https://sepolia.etherscan.io/address/0x7d73d2641d4c68f7b8f11b1ce212645423a0e8b5#events](https://sepolia.etherscan.io/address/0x7d73d2641d4c68f7b8f11b1ce212645423a0e8b5#events)


#### 2. Queue withdrawal via EigenAgent with user signature

Users queue withdrawal via their 6551 EigenAgent from L2 with signatures:
[https://ccip.chain.link/msg/0xa5fb65eff93c716bfad205dcaa0225737fc665e53bee55fb23db07ac5b499018](https://ccip.chain.link/msg/0xa5fb65eff93c716bfad205dcaa0225737fc665e53bee55fb23db07ac5b499018)


# The message makes it's way to L1 resulting in the following Eigenlayer `queueWithdrawal` events:
# [https://sepolia.etherscan.io/tx/0x21b1e008d4fdf5a5a966f0bd65bbb13a1a4187a242a7f7c7ab8fb4c86410b1d7](https://sepolia.etherscan.io/tx/0x21b1e008d4fdf5a5a966f0bd65bbb13a1a4187a242a7f7c7ab8fb4c86410b1d7)

# Withdrawal events can be seen on DelegationManager contract on L1:
# [https://sepolia.etherscan.io/address/0xebbc61ccacf45396ff4b447f353cea404993de98#events](https://sepolia.etherscan.io/address/0xebbc61ccacf45396ff4b447f353cea404993de98#events)


NOTE:
EigenAgent accounts will only execute calls if the signature came from a user who owns the EigenAgentOwner 721 NFTs. See: [https://eips.ethereum.org/EIPS/eip-6551](https://eips.ethereum.org/EIPS/eip-6551)

Each user can only have 1 EigenAgentOwner NFT. We can make them tradeable or soulbound.

EigenAgent accounts are ERC1967 Proxies (can use ERC1167 Minimal Proxies in previous version) and can be upgraded. We can also look at Beacon implementation if we want upgradeability for all accounts.

EigenAgentOwner NFTs are spawn via the AgentFactory (which talkes to 6551 Registry keeps track of EigenAgent 6551 accounts and ownership)
[https://sepolia.etherscan.io/address/0x551c6f21ba8c842ed58c2124a07766e903f24c75#internaltx](https://sepolia.etherscan.io/address/0x551c6f21ba8c842ed58c2124a07766e903f24c75#internaltx)



#### 3. Complete withdrawal from L2 and bridge back to original wallet on L2

We dispatch a call to complete the withdrawal to our SenderCCIP contract from L2:
[https://ccip.chain.link/msg/0xa5280a7ea3bd82c327cc54d1ad0d649a40b23184033e7928bee51f5a0a445adc](https://ccip.chain.link/msg/0xa5280a7ea3bd82c327cc54d1ad0d649a40b23184033e7928bee51f5a0a445adc)

Which executes on L1 with the following Eigenlayer completeWithdrawal events:
[]()


While the tokens are being bridged back, you can see the `messageId` in one of the emitted `Message Sent` event on the ReceiverCCIP contract:
[]()

Copy the `messageId` (topic[1]) on this page and search for it on `https://ccip.chain.link` to view  bridging status:
[]()

Once we wait for the L1 -> L2 bridge back, we can see the token transferred back to the original staker's account:
[]()



### TODO:
- [x] Deploy mock Eigenlayer contracts on Sepolia (Eigenlayer uses Holesky, but Chainlink are on Sepolia)
- [x] Deploy CCIP-BnM ERC20 strategy vault on Eigenlayer
- [ ] Test cross-chain messages for:
    - [x] `depositIntoStrategy` via EigenAgent
    - [x] `queueWithdrawals` via EigenAgent
    - [x] `completeQueuedWithdrawals` via EigenAgent
        - [x] Transfer withdrawn tokens from L1 back to L2
        - [x] Make `mapping(bytes32 withdrawalRoot => Withdrawal)` and `withdrawalRootsSpent` mappings on L1 SenderCCIP bridge, so when the withdrawalRoot is messaged back from L1 we can look up the original staker on L2 to transfer to without needing another signature.
        - [x] Add `setQueueWithdrawalBlock(staker, nonce)` and `getQueueWithdrawalBlock(staker, nonce)` to record the `block.number` needed to re-created the withdrawalRoot to `completeQueuedWithdrawal` via L2.
Queued withdrawals are store in `script/withdrawals-queued/<user_address>/`, and completed withdrawals are recored in `script/withdrawals-completed/<user_address>/`.
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