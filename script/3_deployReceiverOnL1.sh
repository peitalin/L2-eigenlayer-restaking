#!/bin/bash
source .env

echo forge script script/3_deployReceiverOnL1.s.sol:DeployReceiverOnL1Script --rpc-url ethsepolia --broadcast --verify -vvvv

forge script script/3_deployReceiverOnL1.s.sol:DeployReceiverOnL1Script \
    --rpc-url ethsepolia \
    --broadcast \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --private-key $DEPLOYER_KEY \
    --verify \
    -vvvv



### Verify manually if verify failed in previous step
# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x227F4A4e0B9e7E9bdaB98e738bBF7a59143a04c9 \
#     ./src/6551/AgentFactory.sol:AgentFactory

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x35aD715913bF8A7dE9D4dc7DF4230c0c073E6f29 \
#     src/utils/EigenlayerMsgDecoders.sol:EigenlayerMsgDecoders


# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x0aEDf2bfF862E2e8D31951E20f329F3776ceF974 \
#     src/6551/EigenAgent6551.sol:EigenAgent6551

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x302c03Df9Fb7b552E5b941AA47240A29285ae373 \
#     src/utils/EigenlayerMsgEncoders.sol:EigenlayerMsgEncoders


# forge verify-contract \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59 0x779877A7B0D9E8603169DdbD7836e478b4624789) \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x560788e5070f7c369f140f79d87d9584a5a2bb3f \
#     ./src/ReceiverCCIP.sol:ReceiverCCIP