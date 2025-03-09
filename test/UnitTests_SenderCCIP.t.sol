// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {OwnableUpgradeable} from "@openzeppelin-v5-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
import {BaseMessengerCCIP} from "../src/BaseMessengerCCIP.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";


contract UnitTests_SenderCCIP is BaseTestEnvironment {

    uint256 amount = 0.003 ether;
    bytes4 randomFunctionSelector;
    bytes randomMessage;

    function setUp() public {

        setUpLocalEnvironment();

        randomFunctionSelector = bytes4(keccak256("someRandomFunction(uint256)"));
        randomMessage = abi.encodeWithSelector(randomFunctionSelector, 1);
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_SetAndGetSenderHooks() public {

        address newSenderHooks = vm.addr(9981);

        vm.startBroadcast(bob);
        {
            vm.expectRevert(abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                bob
            ));
            senderContract.setSenderHooks(ISenderHooks(newSenderHooks));
        }
        vm.stopBroadcast();

        vm.startBroadcast(deployer);
        {
            // check senderHooks != address(0)
            vm.expectRevert("_senderHooks cannot be address(0)");
            senderContract.setSenderHooks(ISenderHooks(address(0)));
            // set senderHooks
            senderContract.setSenderHooks(ISenderHooks(newSenderHooks));
            // get senderHooks
            vm.assertEq(address(senderContract.getSenderHooks()), newSenderHooks);
        }
        vm.stopBroadcast();
    }

    function test_MockReceive_RandomMessage_WithTokens() public {

        vm.startBroadcast(address(senderContract));
        {
            Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
            destTokenAmounts[0] = Client.EVMTokenAmount({
                token: BaseSepolia.BridgeToken, // CCIP-BnM token address on L2
                amount: amount
            });

            address sender = address(receiverContract);
            Client.Any2EVMMessage memory ccipMessage = Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(sender),
                data: abi.encode(string(
                    randomMessage
                )),
                destTokenAmounts: destTokenAmounts
            });

            // event MessageReceived(
            //     bytes32 indexed messageId,
            //     uint64 indexed sourceChainSelector,
            //     address sender,
            //     address token,
            //     uint256 tokenAmount
            // );
            vm.expectEmit(true, true, true, true);
            emit BaseMessengerCCIP.MessageReceived(
                ccipMessage.messageId,
                ccipMessage.sourceChainSelector,
                sender,
                destTokenAmounts
            );
            vm.expectEmit(true, true, true, true);
            emit SenderCCIP.MatchedReceivedFunctionSelector(randomFunctionSelector);
            // events must be emitted in the right order
            senderContract.mockCCIPReceive(
                ccipMessage
        );

        }
        vm.stopBroadcast();
    }

    function test_MockReceive_RandomMessage_NoTokens() public {

        vm.startBroadcast(address(senderContract));
        {
            Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](0);
            address sender = address(receiverContract);

            Client.Any2EVMMessage memory ccipMessage = Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(sender),
                data: abi.encode(string(
                    randomMessage
                )),
                destTokenAmounts: destTokenAmounts
            });

            Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);
            // event MessageReceived(
            //     bytes32 indexed messageId,
            //     uint64 indexed sourceChainSelector,
            //     address sender,
            //     address token,
            //     uint256 tokenAmount
            // );
            vm.expectEmit(true, true, true, true);
            emit BaseMessengerCCIP.MessageReceived(
                ccipMessage.messageId,
                ccipMessage.sourceChainSelector,
                sender,
                tokenAmounts
            );
            vm.expectEmit(true, true, true, true);
            emit SenderCCIP.MatchedReceivedFunctionSelector(randomFunctionSelector);
            // events must be emitted in the right order
            senderContract.mockCCIPReceive(
                ccipMessage
            );
        }
        vm.stopBroadcast();
    }



}
