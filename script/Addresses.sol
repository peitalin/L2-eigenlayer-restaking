// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// https://test.tokenmanager.chain.link/dashboard/holesky/0xada5cc8a9aab0bc23cfb2ff3a991ab642ade3033

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
    // address constant MagicBnM = 0xc48e0e42B851FE8786fa35CFA12aaCf192C3608a;
    address constant MagicBnM = 0x38Bb3D685f16196963763Ad34CEfa120DD897E71;
    address constant CcipBnM = MagicBnM;
    address constant BridgeToken = MagicBnM;

    address constant Link = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;

    uint256 constant ChainId = 84532;

    // Risk Management Network contract that curses / blesses
    // address constant RMN = ;

    address constant EVM2EVMOnRamp = 0x6486906bB2d85A6c0cCEf2A2831C11A2059ebfea;
}

library EthHolesky {
    //////////////////////////////////////////////
    // ETH Holesky
    //////////////////////////////////////////////
    // Router:
    // 0xb9531b46fE8808fB3659e39704953c2B1112DD43
    //
    // chain selector:
    // 7717148896336251131
    //
    // CCIP-BnM token:
    // 0xada5cc8a9aab0bc23cfb2ff3a991ab642ade3033
    //////////////////////////////////////////////

    address constant Router = 0xb9531b46fE8808fB3659e39704953c2B1112DD43;

    uint64 constant ChainSelector = 7717148896336251131;

    // The CCIP-BnM contract address at the destination chain
    // address constant MagicBnM = 0x8e7aB3b9Ddf313a7c239BFA422aC01d401cb8216;
    address constant MagicBnM = 0xADa5CC8a9aAB0Bc23CFb2ff3a991Ab642aDe3033;
    address constant CcipBnM = MagicBnM;
    address constant BridgeToken = MagicBnM;

    address constant Link = 0x685cE6742351ae9b618F383883D6d1e0c5A31B4B;

    uint256 constant ChainId = 17000;

    // Risk Management Network contract that curses / blesses
    address constant RMN = 0x8607115fd037d4f182b0eBaEC3cF08Df67080d05;

}
