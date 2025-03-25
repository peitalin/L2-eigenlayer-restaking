#!/bin/bash
source .env

echo Getting storage slots for contract...
cast storage 0xAf03f2a302A2C4867d622dE44b213b8F870c0f1a --rpc-url ethsepolia --etherscan-api-key $ETHERSCAN_API_KEY


echo Getting allowance slot...
    ## First level of allowance: mapping(address owner => mapping(address spender => uint256 allowance))
## owner: 0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c
## slot: 1
##
## $ cast index address 0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c 1
## => 0xed155532ee4f3a5456a2c61d1ea319754e196d1446b159dd31d758859d6a392e

## Second level of allowance:
## spender: 0x2a41C5D4C9dbAe6577e90154E85746890cf735D0
## slot: 0xed155532ee4f3a5456a2c61d1ea319754e196d1446b159dd31d758859d6a392e
##
## $ cast index address 0x2a41C5D4C9dbAe6577e90154E85746890cf735D0 0xed155532ee4f3a5456a2c61d1ea319754e196d1446b159dd31d758859d6a392e
## => 0x24b73d817c992471aebb565b9eb85ab910903ac83ec99a5bba93a8ef7d5e0140

## Now query the storage slot as this index:
echo querying allowance slot at: 0x24b73d817c992471aebb565b9eb85ab910903ac83ec99a5bba93a8ef7d5e0140
cast storage 0xAf03f2a302A2C4867d622dE44b213b8F870c0f1a 0x24b73d817c992471aebb565b9eb85ab910903ac83ec99a5bba93a8ef7d5e0140 --rpc-url ethsepolia --etherscan-api-key $ETHERSCAN_API_KEY
# allowance: 0x0000000000000000000000000000000000000000000000000000000000000001
echo

echo querying balance slot at: 0xe03749032392ee97cba968e3381cdd5696e9d27019f56cf676c295cbccc7e27f
cast storage 0xAf03f2a302A2C4867d622dE44b213b8F870c0f1a 0xe03749032392ee97cba968e3381cdd5696e9d27019f56cf676c295cbccc7e27f --rpc-url ethsepolia --etherscan-api-key $ETHERSCAN_API_KEY
# balance: 0x0000000000000000000000000000000000000000000000001d6bc0c48bd40000
