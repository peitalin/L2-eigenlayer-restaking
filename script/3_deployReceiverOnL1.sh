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


# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0x7f9480b3E5C40C38dFB2DD0D2F7b76DDa5CCFE12 \
#     src/6551/EigenAgent6551.sol:EigenAgent6551

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0xE5ca7e7BBF6eb9E6FcD13529Ad16f09D1B9472f7 \
#     src/6551/EigenAgentOwner721.sol:EigenAgentOwner721

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0xdBD194bdfA0472E6515B451a327502cB16de53B8 \
#     src/6551/AgentFactory.sol:AgentFactory

# forge verify-contract \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59 0x779877A7B0D9E8603169DdbD7836e478b4624789) \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0x071b8602abb4f0212b49b8c33490cbb42403492e \
#     ./src/ReceiverCCIP.sol:ReceiverCCIP

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0x7663d666DBbAa83D3D912dcfF69B9a5CD65BEBc1 \
#     ./src/RestakingConnector.sol:RestakingConnector
