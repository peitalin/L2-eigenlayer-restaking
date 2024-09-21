// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

library BaseSepolia {
    //////////////////////////////////////////////
    // Base Sepolia
    //////////////////////////////////////////////
    // Router:
    // 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93
    //
    // chain selector:
    // 10344971235874465080
    //
    // CCIP-BnM token:
    // 0x88A2d74F47a237a62e7A51cdDa67270CE381555e
    //////////////////////////////////////////////

    address constant Router = 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93;

    uint64 constant ChainSelector = 10344971235874465080;

    // The CCIP-BnM contract address at the source chain
    // https://docs.chain.link/ccip/supported-networks/v1_2_0/testnet#base-sepolia
    address constant CcipBnM = 0x88A2d74F47a237a62e7A51cdDa67270CE381555e;

    address constant BridgeToken = CcipBnM;

    address constant Link = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;

    uint256 constant ChainId = 84532;

    // Risk Management Network contract that curses / blesses
    // address constant RMN = ;

    address constant EVM2EVMOnRamp = 0x6486906bB2d85A6c0cCEf2A2831C11A2059ebfea;
}

library EthSepolia {
    //////////////////////////////////////////////
    // ETH Sepolia
    //////////////////////////////////////////////
    // Router:
    // 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59
    //
    // chain selector:
    // 16015286601757825753
    //
    // CCIP-BnM token:
    // 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05
    //////////////////////////////////////////////

    address constant Router = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    uint64 constant ChainSelector = 16015286601757825753;

    address constant CcipBnM = 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05;

    address constant BridgeToken = CcipBnM;

    address constant Link = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    uint256 constant ChainId = 11155111;
}

library ArbSepolia {
    //////////////////////////////////////////////
    // Arb Sepolia
    //////////////////////////////////////////////
    // Router:
    // 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165
    //
    // chain selector:
    // 3478487238524512106
    //
    // CCIP-BnM token:
    // 0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D
    //////////////////////////////////////////////

    address constant Router = 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165;

    uint64 constant ChainSelector = 3478487238524512106;

    // The CCIP-BnM contract address at the source chain
    // https://docs.chain.link/ccip/supported-networks/v1_2_0/testnet#arbitrum-sepolia-ethereum-sepolia
    address constant CcipBnM = 0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D;

    address constant BridgeToken = CcipBnM;

    address constant Link = 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E;

    uint256 constant ChainId = 421614;

    // Risk Management Network contract that curses / blesses
    address constant RMN = 0xbcBDf0aDEDC9a33ED5338Bdb4B6F7CE664DC2e8B;

}