#!/bin/bash
source .env

echo forge script script/6_delegateTo.s.sol:DelegateToScript --rpc-url basesepolia --broadcast -vvvv

forge script script/6_delegateTo.s.sol:DelegateToScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv


## Example DelegateTo CCIP message:
# https://ccip.chain.link/msg/0x241da6f1da5d9a8262c6767486a0134de9e12db1ac3d49e4f8e8ff364c7b6236

## Undelegate Message:
# https://ccip.chain.link/msg/0xd47a04c1d4aa55082e3471669673e07b78475fe870c555075defeecb1b6f581e

## Redeposit Message:
# https://ccip.chain.link/msg/0x3857a387fdcd0d87a1f7c48ac7cdfc26c19cf21ec2b069acf4d67d93e9d94cd7