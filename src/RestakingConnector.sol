// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {console} from "forge-std/Test.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {ISlasher} from "eigenlayer-contracts/src/contracts/interfaces/ISlasher.sol";
import {IEigenPodManager} from "eigenlayer-contracts/src/contracts/interfaces/IEigenPodManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Adminable} from "./utils/Adminable.sol";
import {IRestakingConnector} from "./interfaces/IRestakingConnector.sol";
import {EigenlayerMsgDecoders} from "./utils/EigenlayerMsgDecoders.sol";
import {EigenlayerMsgEncoders} from "./utils/EigenlayerMsgEncoders.sol";
import {FunctionSelectorDecoder} from "./FunctionSelectorDecoder.sol";


contract RestakingConnector is
    IRestakingConnector,
    EigenlayerMsgDecoders,
    Adminable
{

    IDelegationManager public delegationManager;
    IStrategyManager public strategyManager;
    IStrategy public strategy;

    error AddressNull();

    event SetQueueWithdrawalBlock(address indexed, uint256 indexed, uint256 indexed);

    mapping(address => mapping(uint256 => uint256)) private _withdrawalBlock;

    constructor() {
        __Adminable_init();
    }

    function decodeFunctionSelector(bytes memory message) public returns (bytes4) {
        return FunctionSelectorDecoder.decodeFunctionSelector(message);
    }

    function encodeTransferToStakerMsg(bytes32 withdrawalRoot) external returns (bytes memory) {
        EigenlayerMsgEncoders.encodeTransferToStakerMsg(withdrawalRoot);
    }

    /// @dev Checkpoint the actual block.number before queueWithdrawal happens
    /// When dispatching a L2 -> L1 message to queueWithdrawal, the block.number
    /// varies depending on how long it takes to bridge.
    /// We need the block.number to in the following step to
    /// create the withdrawalRoot used to completeWithdrawal.
    function setQueueWithdrawalBlock(address staker, uint256 nonce) external onlyAdminOrOwner {
        _withdrawalBlock[staker][nonce] = block.number;
        emit SetQueueWithdrawalBlock(staker, nonce, block.number);
    }

    function getQueueWithdrawalBlock(address staker, uint256 nonce) public view returns (uint256) {
        return _withdrawalBlock[staker][nonce];
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

    // function isValidSignature(
    //     bytes32 _hash,
    //     bytes memory _signature
    // ) public pure returns (bytes4 magicValue) {
    //     bytes4 constant internal MAGICVALUE = 0x1626ba7e;
    //     // implement some hash/signature scheme
    //     return MAGICVALUE;
    // }

}