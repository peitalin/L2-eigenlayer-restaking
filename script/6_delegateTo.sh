#!/bin/bash
source .env

echo forge script script/6_delegateTo.s.sol:DelegateToScript --rpc-url basesepolia --broadcast -vvvv

forge script script/6_delegateTo.s.sol:DelegateToScript  \
    --rpc-url basesepolia \
    --broadcast \
    -vvvv


## Example DelegateTo CCIP message: