// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";


contract BaseMessenger_Tests is BaseTestEnvironment {

    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error NothingToWithdraw();
    error FailedToWithdrawEth(address owner, address target, uint256 value);

    error DestinationChainNotAllowed(uint64 destinationChainSelector);
    error SourceChainNotAllowed(uint64 sourceChainSelector);

    error SenderNotAllowed(address sender);
    error InvalidReceiverAddress();

    uint256 expiry;
    uint256 amount;
    bytes message;

    function setUp() public {
        // setup forked environments for L2 and L1 contracts
        setUpForkedEnvironment();
        // call params
        amount = 0.0028 ether;
        expiry = block.timestamp + 1 days;
        message = encodeMintEigenAgent(bob);

    }

    /*
     *
     *
     *             Tests
     *
     *
    */

    function test_BaseMessenger_withdrawToken() public {
        /////////////////////////
        // L1 Receiver
        /////////////////////////
        vm.selectFork(ethForkId);

        IERC20_CCIPBnM(address(tokenL1)).drip(address(receiverContract));
        uint256 total = tokenL1.balanceOf(address(receiverContract));

        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        receiverContract.withdrawToken(bob, address(tokenL1));

        vm.prank(deployer);
        receiverContract.withdrawToken(alice, address(tokenL1));

        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        receiverContract.withdrawToken(deployer, address(tokenL1));

        require(tokenL1.balanceOf(alice) == total, "alice should have received all tokens");
        require(tokenL1.balanceOf(address(receiverContract)) == 0, "Sender should have sent all tokens");
    }

    function test_BaseMessenger_withdraw() public {
        /////////////////////////
        // L2 Sender
        /////////////////////////
        vm.selectFork(l2ForkId);

        vm.deal(address(senderContract), 1.1 ether);

        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        senderContract.withdraw(bob);

        vm.prank(deployer);
        senderContract.withdraw(alice);

        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(NothingToWithdraw.selector));
        senderContract.withdraw(deployer);

        require(alice.balance == 1.1 ether, "alice should have received 1 ETH");
        require(address(senderContract).balance == 0, "sender should have sent entire ETH balance");
    }

    function test_BaseMessenger_L1_onlyAllowlistedSender() public {

        /////////////////////////
        // L1 Receiver
        /////////////////////////
        vm.selectFork(ethForkId);

        // these users will revert
        address[] memory usersL1 = new address[](2);
        usersL1[0] = bob;
        usersL1[1] = alice;

        for (uint32 i = 0; i < usersL1.length; ++i) {
            address user = usersL1[i];

            vm.expectRevert(abi.encodeWithSelector(SenderNotAllowed.selector, user));
            receiverContract.mockCCIPReceive(
                Client.Any2EVMMessage({
                    messageId: bytes32(0x0),
                    sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
                    sender: abi.encode(user), // bytes: abi.decode(sender) if coming from an EVM chain.
                    destTokenAmounts: new Client.EVMTokenAmount[](0),
                    data: abi.encode(string(
                        message
                    ))
                })
            );
        }

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
                sender: abi.encode(address(senderContract)), // bytes: abi.decode(sender) if coming from an EVM chain.
                destTokenAmounts: new Client.EVMTokenAmount[](0),
                data: abi.encode(string(
                    message
                ))
            })
        );
        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0),
                data: abi.encode(string(
                    message
                ))
            })
        );
    }

    function test_BaseMessenger_L2_onlyAllowlistedSender() public {

        /////////////////////////
        // L2 Sender
        /////////////////////////
        vm.selectFork(l2ForkId);

        // these users will revert
        address[] memory usersL2 = new address[](2);
        usersL2[0] = bob;
        usersL2[1] = alice;

        for (uint32 i = 0; i < usersL2.length; ++i) {
            address user = usersL2[i];

            vm.expectRevert(abi.encodeWithSelector(SenderNotAllowed.selector, user));
            senderContract.mockCCIPReceive(
                Client.Any2EVMMessage({
                    messageId: bytes32(0x0),
                    sourceChainSelector: EthSepolia.ChainSelector,
                    sender: abi.encode(user),
                    destTokenAmounts: new Client.EVMTokenAmount[](0),
                    data: abi.encode(string(
                        message
                    ))
                })
            );
        }

        senderContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(address(receiverContract)),
                destTokenAmounts: new Client.EVMTokenAmount[](0),
                data: abi.encode(string(
                    message
                ))
            })
        );
        senderContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: EthSepolia.ChainSelector,
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0),
                data: abi.encode(string(
                    message
                ))
            })
        );
    }

    function test_BaseMessenger_L1_onlyAllowlistedDestinationChain() public {

        vm.selectFork(ethForkId);

        uint64 randomChainSelector = 125;

        vm.expectRevert(abi.encodeWithSelector(
            DestinationChainNotAllowed.selector,
            randomChainSelector
        ));
        receiverContract.sendMessagePayNative(
            randomChainSelector, // _destinationChainSelector,
            address(receiverContract), // _receiver,
            string(message),
            address(tokenL1),
            0.1 ether,
            800_000
        );

        receiverContract.sendMessagePayNative(
            BaseSepolia.ChainSelector, // _destinationChainSelector,
            address(receiverContract), // _receiver,
            string(message),
            address(tokenL1),
            0.1 ether,
            800_000
        );
    }

    function test_BaseMessenger_L2_onlyAllowlistedDestinationChain() public {

        vm.selectFork(l2ForkId);

        uint64 randomChainSelector = 125;

        vm.expectRevert(abi.encodeWithSelector(
            DestinationChainNotAllowed.selector,
            randomChainSelector
        ));
        senderContract.sendMessagePayNative(
            randomChainSelector, // _destinationChainSelector,
            address(receiverContract), // _receiver,
            string(message),
            address(tokenL2),
            0.1 ether,
            800_000
        );

        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // _destinationChainSelector,
            address(receiverContract), // _receiver,
            string(message),
            address(tokenL2),
            0.1 ether,
            800_000
        );
    }

    function test_BaseMessenger_L1_onlyAllowlistedSourceChain() public {

        vm.selectFork(ethForkId);

        uint64 randomChainSelector = 333;

        vm.expectRevert(abi.encodeWithSelector(
            SourceChainNotAllowed.selector,
            randomChainSelector
        ));
        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: randomChainSelector, // L2 source chain selector
                sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
                destTokenAmounts: new Client.EVMTokenAmount[](0),
                data: abi.encode(string(
                    message
                ))
            })
        );

        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: BaseSepolia.ChainSelector, // L2 source chain selector
                sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
                destTokenAmounts: new Client.EVMTokenAmount[](0),
                data: abi.encode(string(
                    message
                ))
            })
        );
    }

    function test_BaseMessenger_L2_onlyAllowlistedSourceChain() public {

        vm.selectFork(l2ForkId);

        uint64 randomChainSelector = 333;

        vm.expectRevert(abi.encodeWithSelector(
            SourceChainNotAllowed.selector,
            randomChainSelector
        ));
        senderContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: randomChainSelector, // L2 source chain selector
                sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
                destTokenAmounts: new Client.EVMTokenAmount[](0),
                data: abi.encode(string(
                    message
                ))
            })
        );

        senderContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(0x0),
                sourceChainSelector: EthSepolia.ChainSelector, // L2 source chain selector
                sender: abi.encode(deployer),
                destTokenAmounts: new Client.EVMTokenAmount[](0),
                data: abi.encode(string(
                    message
                ))
            })
        );
    }

    function test_BaseMessenger_L1_ValidateReceiver() public {

        vm.selectFork(ethForkId);

        vm.expectRevert(InvalidReceiverAddress.selector);
        receiverContract.sendMessagePayNative(
            BaseSepolia.ChainSelector, // _destinationChainSelector,
            address(0), // _receiver,
            string(message),
            address(tokenL1),
            0 ether,
            800_000
        );
    }

    function test_BaseMessenger_L2_ValidateReceiver() public {

        vm.selectFork(l2ForkId);

        vm.expectRevert(InvalidReceiverAddress.selector);
        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // _destinationChainSelector,
            address(0), // _receiver,
            string(message),
            address(tokenL2),
            0 ether,
            800_000
        );
    }

    function testFail_BaseMessenger_L2_NotEnoughBalance() public {

        vm.selectFork(l2ForkId);

        vm.prank(deployer);
        senderContract.withdraw(deployer);

        // cheatcode not released yet.
        // vm.expectPartialRevert(NotEnoughBalance.selector);
        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // _destinationChainSelector,
            address(receiverContract), // _receiver,
            string(message),
            address(tokenL2),
            0 ether,
            800_000
        );
    }
}