// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";
import {RouterFees} from "../script/RouterFees.sol";
import {BaseMessengerCCIP} from "../src/BaseMessengerCCIP.sol";


contract BaseMessenger_Tests is BaseTestEnvironment, RouterFees {

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
        uint256 _amount = 0.1 ether;
        uint256 _gasLimit = 800_000;

        vm.startBroadcast(deployerKey);
        {
            uint256 fees = getRouterFeesL1(
                address(senderContract),
                string(message),
                address(tokenL1),
                _amount,
                _gasLimit
            );

            tokenL1.approve(address(receiverContract), _amount);

            vm.expectRevert(abi.encodeWithSelector(
                DestinationChainNotAllowed.selector,
                randomChainSelector
            ));
            receiverContract.sendMessagePayNative{value: fees}(
                randomChainSelector, // _destinationChainSelector,
                address(senderContract), // _receiver,
                string(message),
                address(tokenL1),
                _amount,
                _gasLimit
            );

            receiverContract.sendMessagePayNative{value: fees}(
                BaseSepolia.ChainSelector, // _destinationChainSelector,
                address(senderContract), // _receiver,
                string(message),
                address(tokenL1),
                _amount,
                _gasLimit
            );
        }
        vm.stopBroadcast();
    }

    function test_BaseMessenger_L2_onlyAllowlistedDestinationChain() public {

        vm.selectFork(l2ForkId);

        uint64 randomChainSelector = 125;
        uint256 _amount = 0.1 ether;
        uint256 _gasLimit = 800_000;

        vm.startBroadcast(deployerKey);
        {
            uint256 fees = getRouterFeesL2(
                address(receiverContract),
                string(message),
                address(tokenL2),
                _amount,
                _gasLimit
            );

            tokenL2.approve(address(senderContract), _amount);

            vm.expectRevert(abi.encodeWithSelector(
                DestinationChainNotAllowed.selector,
                randomChainSelector
            ));
            senderContract.sendMessagePayNative{value: fees}(
                randomChainSelector, // _destinationChainSelector,
                address(receiverContract), // _receiver,
                string(message),
                address(tokenL2),
                _amount,
                _gasLimit
            );

            senderContract.sendMessagePayNative{value: fees}(
                EthSepolia.ChainSelector, // _destinationChainSelector,
                address(receiverContract), // _receiver,
                string(message),
                address(tokenL2),
                _amount,
                _gasLimit
            );
        }
    }

    function test_BaseMessenger_L2_NotEnoughGasFees() public {

        vm.selectFork(l2ForkId);

        uint256 _amount = 0.1 ether;
        uint256 _gasLimit = 800_000;

        vm.startBroadcast(deployerKey);
        {
            uint256 fees = 0 ether;
            uint256 feesExpected = getRouterFeesL2(
                address(receiverContract), // _receiver,
                string(message),
                address(tokenL2),
                _amount,
                _gasLimit
            );

            tokenL2.approve(address(senderContract), _amount);

            vm.expectRevert(abi.encodeWithSelector(
                BaseMessengerCCIP.NotEnoughEthGasFees.selector,
                fees,
                feesExpected
            ));
            senderContract.sendMessagePayNative{value: fees}(
                EthSepolia.ChainSelector, // _destinationChainSelector,
                address(receiverContract), // _receiver,
                string(message),
                address(tokenL2),
                _amount,
                _gasLimit
            );
        }
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


    function test_Sender_L2_sendMessagePayNative_Deposit() public {

        ///////////////////////////////////////////////////
        //// Setup Sender contracts on L2 fork
        ///////////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        uint256 execNonce = 0;
        // sign the message for EigenAgent to execute Eigenlayer command
        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            bobKey,
            block.chainid, // destination chainid where EigenAgent lives
            address(strategyManager), // StrategyManager to approve + deposit
            encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            ),
            execNonce,
            expiry
        );

        // messageId (topic[1]): false as we don't know messageId yet
        vm.expectEmit(false, true, false, false);
        emit BaseMessengerCCIP.MessageSent(
            bytes32(0x0),
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            "dispatched call", // default message
            address(BaseSepolia.BridgeToken), // token to send
            0.1 ether,
            address(0), // native gas for fees
            0
        );
        // event MessageSent(
        //     bytes32 indexed messageId,
        //     uint64 indexed destinationChainSelector,
        //     address receiver,
        //     string text,
        //     address token,
        //     uint256 tokenAmount,
        //     address feeToken,
        //     uint256 fees
        // );
        senderContract.sendMessagePayNative{
            value: getRouterFeesL2(
                address(receiverContract),
                string(messageWithSignature),
                address(tokenL2),
                0.1 ether,
                999_000
            )
        }(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature),
            address(tokenL2), // token to send
            0.1 ether, // test sending 0.1e18 tokens
            999_000 // use custom gasLimit for this function
        );
    }

    function test_Receiver_L2_sendMessagePayNative_TransferToAgentOwner() public {

        ///////////////////////////////////////////////////
        //// Receiver contracts on L1 fork
        ///////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        bytes memory messageWithSignature;
        {
            uint256 execNonce = 0;
            bytes32 mockWithdrawalAgentOwnerRoot = bytes32(abi.encode(123));

            message = encodeHandleTransferToAgentOwnerMsg(
                mockWithdrawalAgentOwnerRoot
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signMessageForEigenAgentExecution(
                bobKey,
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager), // StrategyManager to approve + deposit
                message,
                execNonce,
                expiry
            );
        }

        // messageId (topic[1]): false as we don't know messageId yet
        vm.expectEmit(false, true, false, false);
        emit BaseMessengerCCIP.MessageSent(
            bytes32(0x0),
            BaseSepolia.ChainSelector, // destination chain
            address(senderContract),
            "dispatched call", // default message
            address(tokenL1), // token to send
            0 ether,
            address(0), // native gas for fees
            400_000
        );
        // event MessageSent(
        //     bytes32 indexed messageId,
        //     uint64 indexed destinationChainSelector,
        //     address receiver,
        //     string text,
        //     address token,
        //     uint256 tokenAmount,
        //     address feeToken,
        //     uint256 fees
        // );
        receiverContract.sendMessagePayNative{
            value: getRouterFeesL1(
                address(senderContract),
                string(messageWithSignature),
                address(tokenL1),
                0 ether,
                400_000
            )
        }(
            BaseSepolia.ChainSelector, // destination chain
            address(senderContract),
            string(messageWithSignature),
            address(tokenL1), // token to send
            0 ether, // test sending 0 tokens
            400_000 // use custom gasLimit for this function
        );

        vm.expectEmit(false, true, false, false);
        emit BaseMessengerCCIP.MessageSent(
            bytes32(0x0),
            EthSepolia.ChainSelector, // destination chain
            address(senderContract),
            "dispatched call", // default message
            address(EthSepolia.BridgeToken), // token to send
            1 ether,
            address(0), // native gas for fees
            400_000
        );
        receiverContract.sendMessagePayNative{
            value: getRouterFeesL1(
                address(senderContract),
                string(messageWithSignature),
                address(tokenL1),
                1 ether,
                400_000
            )
        }(
            EthSepolia.ChainSelector, // destination chain
            address(senderContract),
            string(messageWithSignature),
            address(tokenL1), // token to send
            1 ether, // test sending 1e18 tokens
            400_000 // use custom gasLimit for this function
        );
    }

}