#!/bin/bash
source .env

echo forge script script/3b_upgradeReceiverOnL1.s.sol:DeployReceiverOnL2Script --rpc-url ethsepolia --broadcast --verify -vvvv

forge script script/3b_upgradeReceiverOnL1.s.sol:UpgradeReceiverOnL1Script \
    --rpc-url ethsepolia \
    --broadcast \
    --verify \
    --private-key $DEPLOYER_KEY \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    -vvvv


# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0xbd1399b675159E2CB25F33f27f6dbdC512aB4005 \
#     ./src/RestakingConnector.sol:RestakingConnector

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0x186af032108ADD15e87b8098ab764376C824f4D5 \
#     src/utils/FunctionSelectorDecoder.sol:FunctionSelectorDecoder

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0xAafB84DAd3FE3439e499a2e868037155820dAb23 \
#     src/utils/EigenlayerMsgDecoders.sol:AgentOwnerSignature

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0xA0E52EAAb41FdC898675452fAF6F01B7b63Cab9d \
#     src/utils/EigenlayerMsgEncoders.sol:EigenlayerMsgEncoders

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.25 \
#     0x2FA8c04CcBdd90E6042b43F547dEdfD932681F6C \
#     src/utils/EigenlayerMsgDecoders.sol:DelegationDecoders
