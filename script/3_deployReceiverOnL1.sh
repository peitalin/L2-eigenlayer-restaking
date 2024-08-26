#!/bin/bash
source .env

echo forge script script/3_deployReceiverOnL1.s.sol:DeployReceiverOnL1Script --rpc-url ethsepolia --broadcast --verify -vvvv

forge script script/3_deployReceiverOnL1.s.sol:DeployReceiverOnL1Script \
    --rpc-url ethsepolia \
    --broadcast \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --private-key $DEPLOYER_KEY \
    --verify \
    # --resume \
    -vvvv


# ### Verify manually if verify failed in previous step
# forge verify-contract \
#     --watch \
#     --constructor-args $(cast abi-encode "constructor(address,address)" 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59 0x779877A7B0D9E8603169DdbD7836e478b4624789) \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x1689aD770c571004fA7F3896F64e49bfc61B564F \
#     ./src/ReceiverCCIP.sol:ReceiverCCIP

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x033351244Ac8E03b484CF06a6A03bBE84352615D \
#     lib/eigenlayer-contracts/lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin


# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x66e79206a5ea3eb7d80ed7fbbaa5240262974594 \
#     ./src/RestakingConnector.sol:RestakingConnector


# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0xeb72aa06bbec8e83b73e97fb06495a6305564882 \
#     ./src/6551/EigenAgentOwner721.sol:EigenAgentOwner721