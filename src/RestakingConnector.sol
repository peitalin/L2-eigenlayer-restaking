// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Adminable} from "./utils/Adminable.sol";

import {IRestakingConnector} from "./IRestakingConnector.sol";
import {EigenlayerDepositMessage, EigenlayerDepositWithSignatureMessage} from "./IRestakingConnector.sol";
import {EigenlayerDepositParams, EigenlayerDepositWithSignatureParams} from "./IRestakingConnector.sol";



contract RestakingConnector is IRestakingConnector, Adminable {

    IDelegationManager public delegationManager;
    IStrategyManager public strategyManager;
    IStrategy public strategy;

    error AddressNull();

    constructor() {
        __Adminable_init();
    }

    function getEigenlayerContracts() public view returns (
        IDelegationManager,
        IStrategyManager,
        IStrategy
    ){
        return (delegationManager, strategyManager, strategy);
    }

    function setEigenlayerContracts(
        IDelegationManager _delegationManager,
        IStrategyManager _strategyManager,
        IStrategy _strategy
    ) public onlyAdminOrOwner {

        if (address(_delegationManager) == address(0)) revert AddressNull();
        if (address(_strategyManager) == address(0)) revert AddressNull();
        if (address(_strategy) == address(0)) revert AddressNull();

        delegationManager = _delegationManager;
        strategyManager = _strategyManager;
        strategy = _strategy;
    }

    function getStrategy() public view returns (IStrategy) {
        return strategy;
    }

    function getStrategyManager() public view returns (IStrategyManager) {
        return strategyManager;
    }

    function decodeDepositMessage(bytes memory message) public returns (EigenlayerDepositMessage memory) {

        bytes32 var1;
        bytes32 var2;
        bytes4 functionSelector;
        uint256 amount;
        address staker;

        assembly {
            var1 := mload(add(message, 32))
            var2 := mload(add(message, 64))
            functionSelector := mload(add(message, 96))
            amount := mload(add(message, 100))
            staker := mload(add(message, 132))
        }

        EigenlayerDepositMessage memory eigenlayerDepositMessage = EigenlayerDepositMessage({
            functionSelector: functionSelector,
            amount: amount,
            staker: staker
        });

        emit EigenlayerDepositParams(functionSelector, amount, staker);

        return eigenlayerDepositMessage;
    }

    function decodeDepositWithSignatureMessage(bytes memory message) public returns (EigenlayerDepositWithSignatureMessage memory) {

        ////////////////////////////
        //// Message payload offsets for assembly destructuring
        ////////////////////////////

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000144 [64]
        // 32e89ace000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40a [96] bytes4 truncates the right
        // f8952159        [100] reads 32 bytes from offset [100] right-to-left up to the function selector
        // 0000000000000000000000003eef6ec7a9679e60cc57d9688e9ec0e6624d687a [132]
        // 000000000000000000000000000000000000000000000000001b5b1bf4c54000 [164] uint256 amount in hex
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [196]
        // 0000000000000000000000000000000000000000000000000000000000015195 [228] expiry
        // 00000000000000000000000000000000000000000000000000000000000000c0 [260] offset: 192 bytes
        // 0000000000000000000000000000000000000000000000000000000000000041 [292] length: 65 bytes
        // 3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee [324]
        // 3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d5 [356]
        // 1c00000000000000000000000000000000000000000000000000000000000000 [388] uin8 = bytes1
        // 00000000000000000000000000000000000000000000000000000000

        bytes32 offset;
        bytes32 length;

        bytes4 functionSelector;
        address _strategy;
        address token;
        uint256 amount;
        address staker;
        uint256 expiry;

        bytes32 sig_offset;
        bytes32 sig_length;
        bytes32 r;
        bytes32 s;
        bytes1 v;

        assembly {
            offset := mload(add(message, 32))
            length := mload(add(message, 64))

            functionSelector := mload(add(message, 96))
            _strategy := mload(add(message, 100))
            token := mload(add(message, 132))
            amount := mload(add(message, 164))
            staker := mload(add(message, 196))
            expiry := mload(add(message, 228))

            sig_offset := mload(add(message, 260))
            sig_length := mload(add(message, 292))

            r := mload(add(message, 324))
            s := mload(add(message, 356))
            v := mload(add(message, 388))
        }

        bytes memory signature = abi.encodePacked(r,s,v);

        require(signature.length == 65, "invalid signature length");

        EigenlayerDepositWithSignatureMessage memory eigenlayerDepositWithSignatureMessage;
        eigenlayerDepositWithSignatureMessage = EigenlayerDepositWithSignatureMessage({
            expiry: expiry,
            strategy: _strategy,
            token: token,
            amount: amount,
            staker: staker,
            signature: signature
        });

        emit EigenlayerDepositWithSignatureParams(functionSelector, amount, staker);

        return eigenlayerDepositWithSignatureMessage;
    }

}