// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {SafeERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20 as IERC20_CCIP} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {SenderCCIP} from "./SenderCCIP.sol";
import {IRestakingConnector} from "./IRestakingConnector.sol";
import {EigenlayerDepositMessage, EigenlayerDepositWithSignatureMessage} from "./IRestakingConnector.sol";



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
        bytes4 functionSelector = decodeFunctionSelector(message);

        (
            IDelegationManager delegationManager,
            IStrategyManager strategyManager,
            IStrategy strategy
        ) = restakingConnector.getEigenlayerContracts();

        IERC20 underlyingToken = strategy.underlyingToken();

        if (functionSelector == 0xf7e784ef) {
            // bytes4(keccak256("depositIntoStrategy(uint256,address)")) == 0xf7e784ef

            EigenlayerDepositMessage memory eigenlayerMsg = restakingConnector.decodeDepositMessage(message);
            // Receiver contract approves eigenlayer StrategyManager for deposits
            underlyingToken.approve(address(strategyManager), eigenlayerMsg.amount);
            // deposit into Eigenlayer
            strategyManager.depositIntoStrategy(strategy, underlyingToken, eigenlayerMsg.amount);
        }

        if (functionSelector == 0x32e89ace) {
            // bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")) == 0x32e89ace

            EigenlayerDepositWithSignatureMessage memory eigen_msg = restakingConnector.decodeDepositWithSignatureMessage(message);
            // Receiver contract approves eigenlayer StrategyManager for deposits
            underlyingToken.approve(address(strategyManager), eigen_msg.amount);
            // deposit into Eigenlayer with user signature
            // function depositIntoStrategyWithSignature(
            //     IStrategy strategy, 0xBd4bcb3AD20E9d85D5152aE68F45f40aF8952159
            //     IERC20 token, 0x3Eef6ec7a9679e60CC57D9688E9eC0e6624D687A
            //     uint256 amount, 0.0077e18 7700000000000000
            //     address staker, 0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c
            //     uint256 expiry, 86421
            //     bytes memory signature, 0x3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c
            // ) external returns (uint256 shares);
            strategyManager.depositIntoStrategyWithSignature(
                IStrategy(eigen_msg.strategy),
                IERC20(eigen_msg.token),
                eigen_msg.amount,
                eigen_msg.staker,
                eigen_msg.expiry,
                eigen_msg.signature
            );
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector, // fetch the source chain identifier (aka selector)
            abi.decode(any2EvmMessage.sender, (address)), // abi-decoding of the sender address,
            abi.decode(any2EvmMessage.data, (string)),
            any2EvmMessage.destTokenAmounts[0].token,
            any2EvmMessage.destTokenAmounts[0].amount
        );
    }
}

