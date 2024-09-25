// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {SenderHooks} from "../src/SenderHooks.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
import {IBaseMessengerCCIP} from "../src/interfaces/IBaseMessengerCCIP.sol";
import {BaseMessengerCCIP} from "../src/BaseMessengerCCIP.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";



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
            vm.expectRevert("Ownable: caller is not the owner");
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

    function test_BaseMessenger_SetBridgeTokens() public {

        address _bridgeTokenL1 = vm.addr(1001);
        address _bridgeTokenL2 = vm.addr(2002);

        vm.expectRevert("_bridgeTokenL1 cannot be address(0)");
        new SenderCCIP(BaseSepolia.Router, address(0), _bridgeTokenL2);

        vm.expectRevert("_bridgeTokenL2 cannot be address(0)");
        new SenderCCIP(BaseSepolia.Router, _bridgeTokenL1, address(0));

        IBaseMessengerCCIP baseMessenger = IBaseMessengerCCIP(address(senderContract));

        vm.startBroadcast(bob);
        {
            vm.expectRevert("Ownable: caller is not the owner");
            baseMessenger.setBridgeTokens(_bridgeTokenL1, _bridgeTokenL2);
        }
        vm.stopBroadcast();

        vm.startBroadcast(deployer);
        {
            vm.expectRevert("_bridgeTokenL1 cannot be address(0)");
            baseMessenger.setBridgeTokens(address(0), _bridgeTokenL2);

            vm.expectRevert("_bridgeTokenL2 cannot be address(0)");
            baseMessenger.setBridgeTokens(_bridgeTokenL1, address(0));

            baseMessenger.setBridgeTokens(_bridgeTokenL1, _bridgeTokenL2);
            vm.assertEq(senderContract.bridgeTokenL1(), _bridgeTokenL1);
            vm.assertEq(senderContract.bridgeTokenL2(), _bridgeTokenL2);
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

            Client.Any2EVMMessage memory ccipMessage = Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(address(deployer)),
                data: abi.encode(string(
                    randomMessage
                )),
                destTokenAmounts: destTokenAmounts
            });

            vm.expectEmit(true, true, true, true);
            emit SenderCCIP.MatchedReceivedFunctionSelector(randomFunctionSelector);

            vm.expectEmit(true, true, true, true);
            emit BaseMessengerCCIP.MessageReceived(
                ccipMessage.messageId,
                ccipMessage.sourceChainSelector,
                address(deployer),
                destTokenAmounts[0].token,
                destTokenAmounts[0].amount
            );
            // event MessageReceived(
            //     bytes32 indexed messageId,
            //     uint64 indexed sourceChainSelector,
            //     address sender,
            //     address token,
            //     uint256 tokenAmount
            // );
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

            Client.Any2EVMMessage memory ccipMessage = Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(address(deployer)),
                data: abi.encode(string(
                    randomMessage
                )),
                destTokenAmounts: destTokenAmounts
            });

            vm.expectEmit(true, true, true, true);
            emit SenderCCIP.MatchedReceivedFunctionSelector(randomFunctionSelector);

            vm.expectEmit(true, true, true, true);
            emit BaseMessengerCCIP.MessageReceived(
                ccipMessage.messageId,
                ccipMessage.sourceChainSelector,
                address(deployer),
                address(0),
                0
            );
            // event MessageReceived(
            //     bytes32 indexed messageId,
            //     uint64 indexed sourceChainSelector,
            //     address sender,
            //     address token,
            //     uint256 tokenAmount
            // );
            senderContract.mockCCIPReceive(
                ccipMessage
            );
        }
        vm.stopBroadcast();
    }

}
