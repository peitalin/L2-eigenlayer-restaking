// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IRestakingConnector} from "./IRestakingConnector.sol";
import {MsgForEigenlayer} from "./RestakingConnector.sol";
import {SenderCCIP} from "./SenderCCIP.sol";

import {IERC20 as IERC20_CCIP} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {console} from "forge-std/Test.sol";


/// Same as SenderCCIP except it handles message deserialization + Eigenlayer contract calls
contract ReceiverCCIP is SenderCCIP {

    IRestakingConnector public restakingConnector;

    /// @notice Constructor initializes the contract with the router address.
    /// @param _router The address of the router contract.
    /// @param _link The address of the link contract.
    /// @param _restakingConnector address of eigenlayer restaking middleware contract.
    constructor(
        address _router,
        address _link,
        address _restakingConnector
    ) SenderCCIP(_router, _link) {
        s_linkToken = IERC20_CCIP(_link);
        // CCIP's IERC20 is different from OZ's IERC20
        restakingConnector = IRestakingConnector(_restakingConnector);
    }

    function getRestakingConnector() public view returns (IRestakingConnector) {
        return restakingConnector;
    }

    function mockCCIPReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) public {
        _ccipReceive(any2EvmMessage);
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address))
        ) // Make sure source chain and sender are allowlisted
    {
        s_lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId
        s_lastReceivedText = abi.decode(any2EvmMessage.data, (string)); // abi-decoding of the sent text
        // Expect one token to be transferred at once, but you can transfer several tokens.
        s_lastReceivedTokenAddress = any2EvmMessage.destTokenAmounts[0].token;
        s_lastReceivedTokenAmount = any2EvmMessage.destTokenAmounts[0].amount;

        if (address(restakingConnector) == address(0)) revert("restakingConnector not set");

        bytes memory message = any2EvmMessage.data;
        MsgForEigenlayer memory msgForEigenlayer = restakingConnector.decodeMessageForEigenlayer(message);

        // if function selector matches...
        // bytes4(keccak256("depositIntoStrategy(uint256,address)")) == 0xf7e784ef

        // abi.encodeWithSelector(bytes4(keccak256("depositIntoStrategy(IStrategy,IERC20,uint256)")), 10, 10);
        // strategyManager.depositIntoStrategy(
        //     IStrategy(address(mockMagicStrategy)),
        //     IERC20(address(mockMagic)),
        //     AMOUNT_TO_DEPOSIT
        // );
        if (msgForEigenlayer.functionSelector == 0xf7e784ef) {

            IStrategy strategy = restakingConnector.getStrategy();
            IERC20 token = strategy.underlyingToken();
            IStrategyManager strategyManager = IStrategyManager(address(restakingConnector.getStrategyManager()));

            // Receiver contract approves eigenlayer StrategyManager for deposits
            token.approve(address(strategyManager), msgForEigenlayer.amount);

            // deposit into Eigenlayer
            strategyManager.depositIntoStrategy(strategy, token, msgForEigenlayer.amount);
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            // msgForEigenlayer.staker,
            abi.decode(any2EvmMessage.data, (string)),
            any2EvmMessage.destTokenAmounts[0].token,
            any2EvmMessage.destTokenAmounts[0].amount
            // msgForEigenlayer.amount
        );
    }
}

