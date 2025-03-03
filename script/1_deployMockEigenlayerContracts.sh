#!/bin/bash
source .env

echo forge script script/1_deployMockEigenlayerContracts.s.sol:DeployMockEigenlayerContractsScript --rpc-url holesky --broadcast -vvvv

# forge script script/1_deployMockEigenlayerContracts.s.sol:DeployMockEigenlayerContractsScript \
#     --rpc-url holesky \
#     --broadcast \
#     --verify  \
#     --private-key $DEPLOYER_KEY \
#     --gas-estimate-multiplier 200 \
#     --priority-gas-price 5 \
#     -vvvv


# ## Verify manually if verify failed in previous step.
forge verify-contract \
    --flatten \
    --watch \
    --rpc-url https://holesky.drpc.org \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --compiler-version v0.8.25 \
    0xADa5CC8a9aAB0Bc23CFb2ff3a991Ab642aDe3033 \
    ./lib/ccip/contracts/src/v0.8/shared/token/ERC20/BurnMintERC20.sol:BurnMintERC20
