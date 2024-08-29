#!/bin/bash
source .env

echo forge script script/8_completeWithdrawal.s.sol:CompleteWithdrawalScript --rpc-url basesepolia --broadcast -vvvv

forge script script/8_completeWithdrawal.s.sol:CompleteWithdrawalScript \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv

##### Example 1:

# We dispatch a call to complete the withdrawal to our SenderCCIP contract from L2:
# [https://ccip.chain.link/msg/0x2bf12fb2f940fb2b3258e1c05d76bd0cdee91c95a34058e1439f152d31dfccb7](https://ccip.chain.link/msg/0x2bf12fb2f940fb2b3258e1c05d76bd0cdee91c95a34058e1439f152d31dfccb7)

# Which executes on L1 with the following Eigenlayer `WithdrawalCompleted` events:
# [https://sepolia.etherscan.io/tx/0x3a55a8ed9bd23c1b2bec5f24be4c7c71da9a21ab2e2f39ba51c5835811df153b#eventlog](https://sepolia.etherscan.io/tx/0x3a55a8ed9bd23c1b2bec5f24be4c7c71da9a21ab2e2f39ba51c5835811df153b#eventlog)


# While the tokens are being bridged back, you can see the `messageId` in one of the emitted `MessageSent` event on the ReceiverCCIP contract:
# [messageId: E0D94E5E264424E2CBD8AE28F9CC7EFFCAE1EBB25424273561828F43944A9208](https://sepolia.etherscan.io/tx/0x3a55a8ed9bd23c1b2bec5f24be4c7c71da9a21ab2e2f39ba51c5835811df153b#eventlog#144)

# Copy the `messageId` (topic[1]) on this page and search for it on `https://ccip.chain.link` to view  bridging status:
# [https://ccip.chain.link/msg/0xe0d94e5e264424e2cbd8ae28f9cc7effcae1ebb25424273561828f43944a9208](https://ccip.chain.link/msg/0xe0d94e5e264424e2cbd8ae28f9cc7effcae1ebb25424273561828f43944a9208)

# Once we wait for the L1 -> L2 bridge back, we can see the token transferred back to the original staker's account:
# [https://sepolia.basescan.org/tx/0x1753d98c605f9fc542e1a612531c634afd6da647b2eb4f1d6d094f74af94e9a8](https://sepolia.basescan.org/tx/0x1753d98c605f9fc542e1a612531c634afd6da647b2eb4f1d6d094f74af94e9a8)



