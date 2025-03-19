// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

library BaseSepolia {
    //////////////////////////////////////////////
    // Base Sepolia
    // https://test.tokenmanager.chain.link/dashboard/base-sepolia/0x886330448089754e998bcefa2a56a91ad240ab60
    //////////////////////////////////////////////

    address constant Router = 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;

    uint64 constant ChainSelector = 10344971235874465080;

    // The Token-BnM contract address at the source chain
    address constant TokenBnM = 0x886330448089754e998BcEfa2a56a91aD240aB60;
    address constant CcipBnM = TokenBnM;
    address constant BridgeToken = TokenBnM;

    address constant Link = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;

    uint256 constant ChainId = 84532;

    // Risk Management Network contract that curses / blesses
    // address constant RMN = ;

    address constant EVM2EVMOnRamp = 0x6486906bB2d85A6c0cCEf2A2831C11A2059ebfea;

    address constant PoolAddress = 0x369a189bE07f42DE9767fBb6d0327eedC129CC15;
}

library EthSepolia {
    //////////////////////////////////////////////
    // ETH Sepolia
    // https://test.tokenmanager.chain.link/dashboard/base-sepolia/0x886330448089754e998bcefa2a56a91ad240ab60
    //////////////////////////////////////////////

    address constant Router = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    uint64 constant ChainSelector = 16015286601757825753;

    address constant TokenBnM = 0xAf03f2a302A2C4867d622dE44b213b8F870c0f1a;
    address constant CcipBnM = TokenBnM;
    address constant BridgeToken = TokenBnM;

    address constant Link = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    uint256 constant ChainId = 11155111;

    address constant PoolAddress = 0xa0f5588fA098B56F28a8ae65CaAa43fEFCAf608c;
}
