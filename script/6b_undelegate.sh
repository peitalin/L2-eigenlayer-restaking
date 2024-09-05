#!/bin/bash
source .env

echo forge script script/6b_undelegate.s.sol:UndelegateScript --rpc-url basesepolia --broadcast -vvvv

forge script script/6b_undelegate.s.sol:UndelegateScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv


## Example Undelegate CCIP message:
# https://ccip.chain.link/msg/0x9d34c12c061307aac296870ac5e14ec885463f3a8bbb9486c75373e8e662fae4