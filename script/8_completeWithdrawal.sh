#!/bin/bash
source .env

echo forge script script/8_completeWithdrawal.s.sol:CompleteWithdrawalScript --rpc-url basesepolia --broadcast -vvvv

forge script script/8_completeWithdrawal.s.sol:CompleteWithdrawalScript  \
    --rpc-url basesepolia \
    --broadcast \
    -vvvv

##### Example 1:

# We dispatch a call to complete the withdrawal to our SenderCCIP contract from L2:
# [https://ccip.chain.link/msg/0x4417c1e8bd060ab8dd0276b86e4d5b8552488639c1bbc71ec3fce0079e484290](https://ccip.chain.link/msg/0x4417c1e8bd060ab8dd0276b86e4d5b8552488639c1bbc71ec3fce0079e484290)

# Which executes on L1 with the following Eigenlayer completeWithdrawal events:
# [https://sepolia.etherscan.io/tx/0x888f2c3b8b1faa9a5fdd6cc14d119ee39d1a8cc9f1c056335cf736edec891844](https://sepolia.etherscan.io/tx/0x888f2c3b8b1faa9a5fdd6cc14d119ee39d1a8cc9f1c056335cf736edec891844)


# While the tokens are being bridged back, you can see the `messageId` in one of the emitted `Message Sent` event on the ReceiverCCIP contract:
# [https://sepolia.etherscan.io/address/0xfccc6216301184b174dd4c7071415ce12ac4ce37#events](https://sepolia.etherscan.io/address/0xfccc6216301184b174dd4c7071415ce12ac4ce37#events)

# Copy the `messageId` (topic[1]) on this page and search for it on `https://ccip.chain.link` to view  bridging status:
# [https://ccip.chain.link/msg/0x827227a70b3efc72869847add23b9264b0fe05354cb0d6cc80ad15530657cf01](https://ccip.chain.link/msg/0x827227a70b3efc72869847add23b9264b0fe05354cb0d6cc80ad15530657cf01)

# Once we wait for the L1 -> L2 bridge back, we can see the token transferred back to the original staker's account:
# [https://sepolia.arbiscan.io/tx/0x7eceaf0d6c6fc55c994df20baad26b25a3a65b4d9601a31c39b29279903219c5](https://sepolia.arbiscan.io/tx/0x7eceaf0d6c6fc55c994df20baad26b25a3a65b4d9601a31c39b29279903219c5)


##### Example 2:

# https://ccip.chain.link/msg/0xf4708d5b1a4ada3e2cb3daf60c0c37fe883dc9e0889f7fe26552d407f2bdd880