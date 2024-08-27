#!/bin/bash
source .env

echo forge script script/6_delegateTo.s.sol:DelegateToScript --rpc-url basesepolia --broadcast -vvvv

forge script script/6_delegateTo.s.sol:DelegateToScript  \
    --rpc-url basesepolia \
    --broadcast \
    --private-key $DEPLOYER_KEY \
    -vvvv


## Example DelegateTo CCIP message:
# https://ccip.chain.link/msg/0x09c9dd5a62626f6d6c9e3e8335809ca2ae5521528c9ed0c3069373f7f50bcc2f