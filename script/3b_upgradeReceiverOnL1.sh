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
#     --compiler-version v0.8.22 \
#     0xbd1399b675159E2CB25F33f27f6dbdC512aB4005 \
#     ./src/RestakingConnector.sol:RestakingConnector

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0xB2aa62553909e3dCeAE83ff55F620dB6F8859BFE \
#     src/utils/EigenlayerMsgEncoders.sol:EigenlayerMsgEncoders

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0xe1483Fa2bbFEADf276b7e3D90b4395041Dfc858f \
#     src/utils/EigenlayerMsgDecoders.sol:AgentOwnerSignature

# forge verify-contract \
#     --watch \
#     --rpc-url ethsepolia \
#     --etherscan-api-key $ETHERSCAN_API_KEY \
#     --compiler-version v0.8.22 \
#     0x24e268615e88aace1e0603cf6c2bec3e8697533b \
#     src/utils/EigenlayerMsgDecoders.sol:DelegationDecoders
