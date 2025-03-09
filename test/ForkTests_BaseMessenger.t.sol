// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {OwnableUpgradeable} from "@openzeppelin-v5-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";
import {IERC20} from "@openzeppelin-v47-contracts/token/ERC20/IERC20.sol";
import {BaseSepolia, EthSepolia} from "../script/Addresses.sol";
import {RouterFees} from "../script/RouterFees.sol";
import {BaseMessengerCCIP} from "../src/BaseMessengerCCIP.sol";
import {NonPayableContract} from "./mocks/NonPayableContract.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {SenderHooks} from "../src/SenderHooks.sol";


contract ForkTests_BaseMessenger is BaseTestEnvironment, RouterFees {

    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees);
    error WithdrawalExceedsBalance(uint256 amount, uint256 currentBalance);
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
        message = encodeMintEigenAgentMsg(bob);

    }

    /*
     *
     *
     *             Tests
     *
     *
    */

    function test_BaseMessenger_withdrawToken() public {

        // L1 Receiver
        vm.selectFork(ethForkId);

        IERC20_CCIPBnM(address(tokenL1)).drip(address(receiverContract));
        uint256 totalWithdraw = tokenL1.balanceOf(address(receiverContract));
        uint256 halfWithdraw = totalWithdraw / 2;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(
            OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
            bob
        ));
        receiverContract.withdrawToken(bob, address(tokenL1), totalWithdraw);

        // withdraw half, twice (all tokens)
        vm.prank(deployer);
        receiverContract.withdrawToken(alice, address(tokenL1), halfWithdraw);
        vm.prank(deployer);
        receiverContract.withdrawToken(alice, address(tokenL1), halfWithdraw);

        require(tokenL1.balanceOf(alice) == totalWithdraw, "alice should have received all tokens");
        require(tokenL1.balanceOf(address(receiverContract)) == 0, "Sender should have sent all tokens");

        vm.expectRevert(abi.encodeWithSelector(
            WithdrawalExceedsBalance.selector,
            totalWithdraw  * 2,
            tokenL1.balanceOf(address(receiverContract))
        ));
        vm.prank(deployer);
        receiverContract.withdrawToken(deployer, address(tokenL1), totalWithdraw * 2);
    }

    function test_BaseMessenger_withdraw() public {

        // L2 Sender
        vm.selectFork(l2ForkId);

        vm.deal(address(senderContract), 1.1 ether);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(
            OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
            bob
        ));
        senderContract.withdraw(bob, address(bob).balance);

        vm.prank(deployer);
        senderContract.withdraw(alice, address(senderContract).balance);

        require(alice.balance == 1.1 ether, "alice should have received 1.1 ETH");
        require(address(senderContract).balance == 0, "sender should have sent entire ETH balance");

        vm.expectRevert(abi.encodeWithSelector(
            WithdrawalExceedsBalance.selector,
            address(senderContract).balance + 0.1 ether,
            address(senderContract).balance
        ));
        vm.prank(deployer);
        senderContract.withdraw(deployer, address(senderContract).balance + 0.1 ether);
    }

    function test_BaseMessenger_withdrawFailure() public {

        // L2 Sender
        vm.selectFork(l2ForkId);

        vm.deal(address(senderContract), 1.1 ether);

        NonPayableContract nonPayableContract = new NonPayableContract();

        uint256 withdrawAmount = 1.1 ether;

        vm.expectRevert(
            abi.encodeWithSelector(
                FailedToWithdrawEth.selector,
                deployer, // owner
                address(nonPayableContract), // target
                withdrawAmount
            )
        );
        vm.prank(deployer);
        senderContract.withdraw(address(nonPayableContract), withdrawAmount);

        vm.assertEq(address(nonPayableContract).balance, 0);
        vm.assertEq(address(senderContract).balance, withdrawAmount);
    }

    function test_BaseMessenger_L1_onlyAllowlistedSender() public {

        // L1 Receiver
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

        // L2 Sender
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

        // L1 Receiver
        vm.selectFork(ethForkId);

        uint64 randomChainSelector = 125;
        uint256 _gasLimit = 800_000;
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1),
            amount: 0.1 ether
        });

        vm.startBroadcast(deployerKey);
        {
            uint256 fees = getRouterFeesL1(
                address(senderContract),
                string(message),
                tokenAmounts,
                _gasLimit
            );

            tokenL1.approve(address(receiverContract), tokenAmounts[0].amount);

            vm.expectRevert(abi.encodeWithSelector(
                DestinationChainNotAllowed.selector,
                randomChainSelector
            ));
            receiverContract.sendMessagePayNative{value: fees}(
                randomChainSelector, // _destinationChainSelector,
                address(senderContract), // _receiver,
                string(message),
                tokenAmounts,
                _gasLimit
            );

            receiverContract.sendMessagePayNative{value: fees}(
                BaseSepolia.ChainSelector, // _destinationChainSelector,
                address(senderContract), // _receiver,
                string(message),
                tokenAmounts,
                _gasLimit
            );
        }
        vm.stopBroadcast();
    }

    function test_BaseMessenger_L2_onlyAllowlistedDestinationChain() public {

        // L2 Sender
        vm.selectFork(l2ForkId);

        uint64 randomChainSelector = 125;
        uint256 _gasLimit = 800_000;

        vm.deal(deployer, 1 ether);

        vm.startBroadcast(deployerKey);
        {
            uint256 fees = getRouterFeesL2(
                address(receiverContract),
                string(message),
                new Client.EVMTokenAmount[](0),
                _gasLimit
            );

            vm.expectRevert(abi.encodeWithSelector(
                DestinationChainNotAllowed.selector,
                randomChainSelector
            ));
            senderContract.sendMessagePayNative{value: fees}(
                randomChainSelector, // _destinationChainSelector,
                address(receiverContract), // _receiver,
                string(message),
                new Client.EVMTokenAmount[](0),
                _gasLimit
            );

            senderContract.sendMessagePayNative{value: fees}(
                EthSepolia.ChainSelector, // _destinationChainSelector,
                address(receiverContract), // _receiver,
                string(message),
                new Client.EVMTokenAmount[](0),
                _gasLimit
            );
        }
    }

    function test_BaseMessenger_L2_NotEnoughGasFees() public {

        // L2 Sender
        vm.selectFork(l2ForkId);

        uint256 _gasLimit = 800_000;
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL2),
            amount: 0.01 ether
        });

        IERC20(tokenL2).approve(address(senderContract), tokenAmounts[0].amount);

        vm.startBroadcast(deployerKey);
        {
            uint256 fees = 0 ether;
            uint256 feesExpected = getRouterFeesL2(
                address(receiverContract), // _receiver,
                string(encodeDepositIntoStrategyMsg(
                    address(strategy),
                    tokenAmounts[0].token,
                    tokenAmounts[0].amount
                )),
                tokenAmounts,
                _gasLimit
            );

            tokenL2.approve(address(senderContract), tokenAmounts[0].amount);

            vm.expectRevert(abi.encodeWithSelector(
                BaseMessengerCCIP.NotEnoughEthGasFees.selector,
                fees,
                feesExpected
            ));
            senderContract.sendMessagePayNative{value: fees}(
                EthSepolia.ChainSelector, // _destinationChainSelector,
                address(receiverContract), // _receiver,
                string(encodeDepositIntoStrategyMsg(
                    address(strategy),
                    tokenAmounts[0].token,
                    tokenAmounts[0].amount
                )),
                tokenAmounts,
                _gasLimit
            );
        }
    }

    function test_BaseMessenger_L2_RefundsExcessGasFees() public {

        // L2 Sender
        vm.selectFork(l2ForkId);

        uint256 _gasLimit = 800_000;

        vm.deal(deployer, 1 ether);
        vm.startBroadcast(deployerKey);
        {
            uint256 balanceBefore = address(deployer).balance;
            uint256 fees = 1 ether;
            uint256 feesExpected = getRouterFeesL2(
                address(receiverContract), // _receiver,
                string(message),
                new Client.EVMTokenAmount[](0),
                _gasLimit
            );
            require(fees > feesExpected, "Fees should be greater than expected");

            senderContract.sendMessagePayNative{value: fees}(
                EthSepolia.ChainSelector, // _destinationChainSelector,
                address(receiverContract), // _receiver,
                string(message),
                new Client.EVMTokenAmount[](0),
                _gasLimit
            );

            uint256 balanceAfter = address(deployer).balance;
            uint256 expectedBalance = balanceBefore - feesExpected;
            require(balanceAfter == expectedBalance, "Did not refund excess ETH");
        }
    }

    function test_BaseMessenger_L1_onlyAllowlistedSourceChain() public {

        // L1 Receiver
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

        // L2 Sender
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

        // L1 Receiver
        vm.selectFork(ethForkId);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1),
            amount: 0 ether
        });

        vm.expectRevert(InvalidReceiverAddress.selector);
        receiverContract.sendMessagePayNative(
            BaseSepolia.ChainSelector, // _destinationChainSelector,
            address(0), // _receiver,
            string(message),
            tokenAmounts,
            800_000
        );
    }

    function test_BaseMessenger_L2_ValidateReceiver() public {

        vm.selectFork(l2ForkId);

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL2),
            amount: 0 ether
        });

        vm.expectRevert(InvalidReceiverAddress.selector);
        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // _destinationChainSelector,
            address(0), // _receiver,
            string(message),
            tokenAmounts,
            800_000
        );
    }

    function test_RevertWhen_BaseMessenger_L2_NotEnoughEthGasFees() public {

        // L2 Sender
        vm.selectFork(l2ForkId);
        uint256 _gasLimit = 800_000;

        vm.prank(deployer);
        senderContract.withdraw(deployer, address(senderContract).balance);

        uint256 expectedFees = getRouterFeesL2(
            address(receiverContract),
            string(message),
            new Client.EVMTokenAmount[](0), // empty array
            _gasLimit
        );

        uint stingyFees = 1 gwei;

        vm.expectRevert(abi.encodeWithSelector(
            BaseMessengerCCIP.NotEnoughEthGasFees.selector,
            stingyFees,
            expectedFees
        ));
        senderContract.sendMessagePayNative{value: stingyFees}(
            EthSepolia.ChainSelector, // _destinationChainSelector,
            address(receiverContract), // _receiver,
            string(message),
            new Client.EVMTokenAmount[](0),
            _gasLimit
        );
    }

    function test_Sender_L2_sendMessagePayNative_Deposit() public {

        // Setup L2 Sender contracts on L2 fork
        vm.selectFork(l2ForkId);

        uint256 execNonce = 0;
        // sign the message for EigenAgent to execute Eigenlayer command
        bytes memory messageWithSignature = signMessageForEigenAgentExecution(
            bobKey,
            address(eigenAgent),
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

        vm.deal(deployer, 1 ether);
        vm.startBroadcast(deployer);
        {
            tokenL2.approve(address(senderContract), 0.1 ether);

            Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({
                token: address(tokenL2),
                amount: 0.1 ether
            });
            // messageId (topic[1]): false as we don't know messageId yet
            vm.expectEmit(false, true, false, false);
            emit BaseMessengerCCIP.MessageSent(
                bytes32(0x0), // indexed messageId
                EthSepolia.ChainSelector, // indexed destinationChainSelector
                address(receiverContract), // receiver
                tokenAmounts,
                address(0), // native gas for fees
                999_000 // fees
            );
            senderContract.sendMessagePayNative{
                value: getRouterFeesL2(
                    address(receiverContract),
                    string(messageWithSignature),
                    tokenAmounts,
                    999_000
                )
            }(
                EthSepolia.ChainSelector, // destination chain
                address(receiverContract),
                string(messageWithSignature),
                tokenAmounts,
                999_000 // use custom gasLimit for this function
            );
        }
    }

    function test_Receiver_L2_sendMessagePayNative_TransferToAgentOwner() public {

        // Receiver contracts on L1 fork
        vm.selectFork(ethForkId);

        bytes memory messageWithSignature;
        {
            uint256 execNonce = 0;
            message = encodeTransferToAgentOwnerMsg(bob);
            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signMessageForEigenAgentExecution(
                bobKey,
                address(eigenAgent),
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager), // StrategyManager to approve + deposit
                message,
                execNonce,
                expiry
            );
        }

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(tokenL1),
            amount: 0.01 ether
        });
        require(IERC20(tokenL1).balanceOf(deployer) > 0.01 ether, "Deployer should have enough tokenL1");

        // messageId (topic[1]): false as we don't know messageId yet
        vm.startBroadcast(deployer);
        {
            IERC20(tokenL1).approve(address(receiverContract), tokenAmounts[0].amount);

            vm.expectEmit(false, true, false, false);
            emit BaseMessengerCCIP.MessageSent(
                bytes32(0x0), // indexed messageId
                BaseSepolia.ChainSelector, // destinationChainSelector
                address(senderContract), // receiver
                tokenAmounts,
                address(0), // native gas for fees
                400_000 // gasLimit
            );
            receiverContract.sendMessagePayNative{
                value: getRouterFeesL1(
                    address(senderContract),
                    string(messageWithSignature),
                    tokenAmounts,
                    400_000
                )
            }(
                BaseSepolia.ChainSelector, // _destinationChainSelector,
                address(senderContract),
                string(messageWithSignature),
                tokenAmounts,
                    400_000 // use custom gasLimit for this function
            );
        }
        vm.stopBroadcast();
    }

    function test_Receiver_L2_sendMessagePayNative_OutOfGas() public {

        // L1 fork
        vm.selectFork(ethForkId);

        bytes memory messageWithSignature;
        {
            uint256 execNonce = 0;
            message = encodeTransferToAgentOwnerMsg(bob);
            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signMessageForEigenAgentExecution(
                bobKey,
                address(eigenAgent),
                block.chainid, // destination chainid where EigenAgent lives
                address(strategyManager), // StrategyManager to approve + deposit
                message,
                execNonce,
                expiry
            );
        }

        // test out of gas error
        uint256 hugeGasFees = 3_000_000;

        vm.selectFork(ethForkId);
        uint256 fees = getRouterFeesL1(
            address(receiverContract),
            string(messageWithSignature),
            new Client.EVMTokenAmount[](0),
            hugeGasFees
        );

        // send receiverContract's ETH balance to bob, to trigger NotEnoughBalance error
        vm.prank(address(receiverContract));
        (
            bool _success,
            // bytes memory _result
        ) = address(bob).call{value: address(receiverContract).balance}("");
        require(_success, "bob should receive ETH");

        vm.expectRevert(abi.encodeWithSelector(BaseMessengerCCIP.NotEnoughBalance.selector, 0, fees));
        // don't send gas to receiver contract
        vm.prank(address(receiverContract));
        receiverContract.sendMessagePayNative(
            BaseSepolia.ChainSelector, // _destinationChainSelector,
            address(senderContract),
            string(messageWithSignature),
            new Client.EVMTokenAmount[](0),
            hugeGasFees // use custom gasLimit for this function
        );

        require(address(receiverContract).balance == 0, "receiverCCIP should not have any ETH");
    }

   function test_BaseMessenger_UnsupportedFunctionCall() public {

        // L2 Sender
        vm.selectFork(l2ForkId);

        uint256 _amount = 0 ether;
        uint256 _gasLimit = 800_000;

        vm.deal(deployer, 1 ether);

        bytes4 randomFunctionSelector = bytes4(keccak256("randomFunctionSelector()"));

        bytes memory unsupportedMessage = abi.encodeWithSelector(
            randomFunctionSelector
        );

        vm.startBroadcast(deployerKey);
        {
            uint256 fees = getRouterFeesL2(
                address(receiverContract),
                string(unsupportedMessage),
                new Client.EVMTokenAmount[](0),
                _gasLimit
            );

            tokenL2.approve(address(senderContract), _amount);

            vm.expectRevert(abi.encodeWithSelector(
                SenderHooks.UnsupportedFunctionCall.selector,
                randomFunctionSelector
            ));
            senderContract.sendMessagePayNative{value: fees}(
                EthSepolia.ChainSelector, // _destinationChainSelector,
                address(receiverContract), // _receiver,
                string(unsupportedMessage),
                new Client.EVMTokenAmount[](0),
                _gasLimit
            );
        }
        vm.stopBroadcast();
    }

}