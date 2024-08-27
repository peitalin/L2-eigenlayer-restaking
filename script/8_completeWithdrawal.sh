#!/bin/bash
source .env

echo forge script script/8_completeWithdrawal.s.sol:CompleteWithdrawalScript --rpc-url basesepolia --broadcast -vvvv

forge script script/8_completeWithdrawal.s.sol:CompleteWithdrawalScript \
    --rpc-url basesepolia \
    --broadcast \
    -vvvv

##### Example 1:

# We dispatch a call to complete the withdrawal to our SenderCCIP contract from L2:
# [https://ccip.chain.link/msg/0x3a02206482f0148c74cb4b34a631b998502c754d198abc378e10ccaf6c725825](https://ccip.chain.link/msg/0x3a02206482f0148c74cb4b34a631b998502c754d198abc378e10ccaf6c725825)

# Which executes on L1 with the following Eigenlayer completeWithdrawal events:
# [https://sepolia.etherscan.io/tx/0xc4e336ee410598fff9e6951b176b11e4ac6f3d0df2768eb79a986ada7e829037#eventlog](https://sepolia.etherscan.io/tx/0xc4e336ee410598fff9e6951b176b11e4ac6f3d0df2768eb79a986ada7e829037#eventlog)


# While the tokens are being bridged back, you can see the `messageId` in one of the emitted `Message Sent` event on the ReceiverCCIP contract:
# [https://sepolia.etherscan.io/address/0x4c854b17250582413783b96e020e5606a561eddc#events](https://sepolia.etherscan.io/address/0x4c854b17250582413783b96e020e5606a561eddc#events)

# Copy the `messageId` (topic[1]) on this page and search for it on `https://ccip.chain.link` to view  bridging status:
# [https://ccip.chain.link/msg/0xf6165cfb76cceaebbb93e9b49f7ac373547e51368bf9048c59c90c2d774fc42e](https://ccip.chain.link/msg/0xf6165cfb76cceaebbb93e9b49f7ac373547e51368bf9048c59c90c2d774fc42e)

# Once we wait for the L1 -> L2 bridge back, we can see the token transferred back to the original staker's account:
# [https://sepolia.basescan.org/tx/0xf4824d3fc1925a91f5cec814d6e03985092c38e7838c38f83d755a698923446c](https://sepolia.basescan.org/tx/0xf4824d3fc1925a91f5cec814d6e03985092c38e7838c38f83d755a698923446c)



