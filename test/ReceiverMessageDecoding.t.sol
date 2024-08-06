// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {IRouterClient, WETH9, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {MsgForEigenlayer} from "../src/RestakingConnector.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IRestakingConnector} from "../src/IRestakingConnector.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";


contract MessagePassingTest is Test {

    uint256 public deployerKey;
    address public deployer;

    function setUp() public {
		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
    }

    function test_ReceiverContractDecodesEVMMessage() public {

        vm.startBroadcast(deployerKey);

        address router = address(0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59);
        address link = address(0x779877A7B0D9E8603169DdbD7836e478b4624789);

        // Deploy L2 msg decoder for Eigenlayer
        RestakingConnector restakingConnector = new RestakingConnector();
        // Deploy receiver contract
        ReceiverCCIP receiverContract = new ReceiverCCIP(router, link, address(restakingConnector));
        // ProgrammableTokenTransfers receiverContract = new ProgrammableTokenTransfers(router, link, address(restakingConnector));

        // Set allowlists
        uint64 _sourceChainSelector = 3478487238524512106; // Arb Sepolia
        receiverContract.allowlistSourceChain(_sourceChainSelector, true);

        bytes memory sender = hex"0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c";
        receiverContract.allowlistSender(abi.decode(sender, (address)), true);
        vm.stopBroadcast();

        ///////////////////////////////////////////
        // Prepare CCIP Message
        ///////////////////////////////////////////

        // bytes memory message = hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000044f7e784ef00000000000000000000000000000000000000000000000000000000000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c00000000000000000000000000000000000000000000000000000000";
        // incoming CCIP message is in string format:
        string memory message1 = string(abi.encodeWithSelector(
            bytes4(keccak256("testDecoding(uint256,address)")),
            2,
            deployer
        ));
        // which is decoded into bytes
        bytes memory message = abi.encode(message1);
        // console.logBytes(message);

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05, // CCIP-BnM token address on Eth Sepolia.
            amount: 0.01 ether
        });

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0x598fff8ee56c84a5d8793c1ac075501711392720209f72ae3cfb445d4116d272),
            sourceChainSelector: _sourceChainSelector,
            sender: sender, // bytes: abi.decode(sender) if coming from an EVM chain.
            data: message, // bytes: payload sent in original message.
            destTokenAmounts: destTokenAmounts // Tokens and their amounts in their destination chain representation.
        });

        // Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
        //     receiver: abi.encode(_receiver), // ABI-encoded receiver address
        //     data: abi.encode(_text), // ABI-encoded string
        //     tokenAmounts: tokenAmounts, // The amount and type of token being transferred
        //     extraArgs: Client._argsToBytes(
        //         // gasLimit set to 20_000 on purpose to force the execution to fail on the destination chain
        //         Client.EVMExtraArgsV1({gasLimit: 20_000})
        //     ),
        //     // Set the feeToken to a LINK token address
        //     feeToken: address(s_linkToken)
        // });

        // simulate router sending message to receiverContract on L1
        vm.startBroadcast(router);
        receiverContract.ccipReceive(any2EvmMessage);
        vm.stopBroadcast();
    }

    function test_DeserializeEigenlayerMessage() public pure {

        // 0000000000000000000000000000000000000000000000000000000000000020
        // 0000000000000000000000000000000000000000000000000000000000000044
        // f7e784ef00000000000000000000000000000000000000000000000000000000
        // 000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a
        // 1b7b6c2c00000000000000000000000000000000000000000000000000000000
        bytes memory message = hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000044f7e784ef00000000000000000000000000000000000000000000000000000000000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c00000000000000000000000000000000000000000000000000000000";

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

        bytes4 functionSelector2 = bytes4(keccak256("depositIntoStrategy(uint256,address)"));

        require(functionSelector == functionSelector2, "functionSelectors do not match");

        MsgForEigenlayer memory msgForEigenlayer = MsgForEigenlayer({
            functionSelector: functionSelector,
            amount: amount,
            staker: staker
        });

        console.log("functionSelector:");
        console.logBytes4(msgForEigenlayer.functionSelector);
        require(msgForEigenlayer.functionSelector == bytes4(0xf7e784ef), "decoded incorrect msgForEigenlayer.functionSelector");

        console.log("amount:");
        console.log(msgForEigenlayer.amount);

        require(msgForEigenlayer.amount == 2, "decoded incorrect msgForEigenlayer.amount");

        console.log("staker:");
        console.log(msgForEigenlayer.staker);
        require(msgForEigenlayer.staker == 0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c, "decoded incorrect msgForEigenlayer.staker");
    }

}
