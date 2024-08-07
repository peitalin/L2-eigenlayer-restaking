// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {IRouterClient, WETH9, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/IRestakingConnector.sol";
import {EigenlayerDepositParams, EigenlayerDepositMessage} from "../src/IRestakingConnector.sol";

import {EIP1271SignatureUtils} from "eigenlayer-contracts/src/contracts/libraries/EIP1271SignatureUtils.sol";


contract MessagePassingTest is Test {

    uint256 public deployerKey;
    address public deployer;

    function setUp() public {
		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

    }

    function decodeFunctionSelector(bytes memory message) public returns (bytes4) {

        bytes32 offset;
        bytes32 length;
        bytes4 functionSelector;

        assembly {
            offset := mload(add(message, 32))
            length := mload(add(message, 64))
            functionSelector := mload(add(message, 96))
        }

        return functionSelector;
    }

    function test_DecodeFunctionSelectors() public {

        bytes memory message1 = hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000044f7e784ef00000000000000000000000000000000000000000000000000000000000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c00000000000000000000000000000000000000000000000000000000";
        bytes4 functionSelector1 = decodeFunctionSelector(message1);
        require(functionSelector1 == 0xf7e784ef, "wrong functionSelector");

        bytes memory message2 = abi.encode(string(abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")),
            86421,
            0xBd4bcb3AD20E9d85D5152aE68F45f40aF8952159,
            0x3Eef6ec7a9679e60CC57D9688E9eC0e6624D687A,
            0.0077 ether,
            0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c,
            hex"3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c"
        )));
        bytes4 functionSelector2 = decodeFunctionSelector(message2);
        require(functionSelector2 == 0x32e89ace, "wrong functionSelector");
    }

    function test_DecodeEigenlayerMessage() public pure {

        // 0000000000000000000000000000000000000000000000000000000000000020
        // 0000000000000000000000000000000000000000000000000000000000000044
        // f7e784ef00000000000000000000000000000000000000000000000000000000
        // 000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a
        // 1b7b6c2c00000000000000000000000000000000000000000000000000000000
        bytes memory message = hex"00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000044f7e784ef00000000000000000000000000000000000000000000000000000000000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c00000000000000000000000000000000000000000000000000000000";

        bytes32 offset;
        bytes32 length;
        bytes4 functionSelector;
        uint256 amount;
        address staker;

        assembly {
            offset := mload(add(message, 32))
            length := mload(add(message, 64))
            functionSelector := mload(add(message, 96))
            amount := mload(add(message, 100))
            staker := mload(add(message, 132))
        }

        bytes4 functionSelector2 = bytes4(keccak256("depositIntoStrategy(uint256,address)"));

        require(functionSelector == functionSelector2, "functionSelectors do not match");

        EigenlayerDepositMessage memory emsg = EigenlayerDepositMessage({
            functionSelector: functionSelector,
            amount: amount,
            staker: staker
        });

        require(emsg.functionSelector == bytes4(0xf7e784ef), "decoded incorrect EigenlayerDepositMessage.functionSelector");
        require(emsg.amount == 2, "decoded incorrect EigenlayerDepositMessage.amount");
        require(emsg.staker == 0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c, "decoded incorrect EigenlayerDepositMessage.staker");
    }


    function test_DecodeEigenlayerMessage_WithSignature() public pure {

        // encode message payload
        bytes memory message_bytes = abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)")),
            86421,
            0xBd4bcb3AD20E9d85D5152aE68F45f40aF8952159,
            0x3Eef6ec7a9679e60CC57D9688E9eC0e6624D687A,
            0.0077 ether,
            0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c,
            hex"3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c"
        );
        // CCIP turns the message into string when sending
        bytes memory message = abi.encode(string(message_bytes));
        console.log("message_str");
        console.logBytes(message);

        ////////////////////////////
        //// Message payload offsets for assembly decoding
        ////////////////////////////

        // 0000000000000000000000000000000000000000000000000000000000000020 [32]
        // 0000000000000000000000000000000000000000000000000000000000000144 [64]
        // 32e89ace00000000000000000000000000000000000000000000000000000000 [96] bytes4 truncates every on the right
        // 00015195 [100] reads 32 bytes from offset [100] right-to-left
        // 000000000000000000000000bd4bcb3ad20e9d85d5152ae68f45f40af8952159 [132]
        // 0000000000000000000000003eef6ec7a9679e60cc57d9688e9ec0e6624d687a [164]
        // 000000000000000000000000000000000000000000000000001b5b1bf4c54000 [196] uint256 in hex
        // 0000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c [228]
        // 00000000000000000000000000000000000000000000000000000000000000c0 [260] offset: 192 bytes
        // 0000000000000000000000000000000000000000000000000000000000000041 [292] length: 65 bytes
        // 3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee [324]
        // 3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d5 [356]
        // 1c00000000000000000000000000000000000000000000000000000000000000 [388] uint8 = bytes1
        // 00000000000000000000000000000000000000000000000000000000

        bytes32 offset;
        bytes32 length;

        bytes4 functionSelector;
        uint256 expiry;
        address _strategy;
        address _token;
        uint256 amount;
        address staker;

        bytes32 sig_offset;
        bytes32 sig_length;
        bytes32 r;
        bytes32 s;
        bytes1 v;

        assembly {
            offset := mload(add(message, 32))
            length := mload(add(message, 64))

            functionSelector := mload(add(message, 96))
            expiry := mload(add(message, 100))
            _strategy := mload(add(message, 132))
            _token := mload(add(message, 164))
            amount := mload(add(message, 196))
            staker := mload(add(message, 228))

            sig_offset := mload(add(message, 260))
            sig_length := mload(add(message, 292))

            r := mload(add(message, 324))
            s := mload(add(message, 356))
            v := mload(add(message, 388))
        }

        console.log("offset:");
        console.logBytes32(offset);

        console.log("length:");
        console.logBytes32(length);

        console.log("functionSelector:");
        console.logBytes4(functionSelector);

        console.log("expiry:");
        console.log(expiry);

        console.log("strategy:");
        console.log(_strategy);

        console.log("token:");
        console.log(_token);

        console.log("amount:");
        console.log(amount);

        console.log("staker:");
        console.log(staker);

        console.log("sig_offset:");
        console.logBytes32(sig_offset);

        console.log("sig_length:");
        console.logBytes32(sig_length);

        console.log("r:");
        console.logBytes32(r);

        console.log("s:");
        console.logBytes32(s);

        console.log("v:");
        console.logBytes1(v);

        bytes memory signature = abi.encodePacked(r,s,v);
        console.log("signature:");
        console.logBytes(signature);

        // function depositIntoStrategyWithSignature(
        //     IStrategy strategy, 0xBd4bcb3AD20E9d85D5152aE68F45f40aF8952159
        //     IERC20 token, 0x3Eef6ec7a9679e60CC57D9688E9eC0e6624D687A
        //     uint256 amount, 0.0077e18 7700000000000000
        //     address staker, 0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c
        //     uint256 expiry, 86421
        //     bytes memory signature, 0x3de99eb6c4e298a2332589fdcfd751c8e1adf9865da06eff5771b6c59a41c8ee3b8ef0a097ef6f09deee5f94a141db1a8d59bdb1fd96bc1b31020830a18f76d51c
        // ) external returns (uint256 shares);

        require(signature.length == 65, "invalid signature length");
        bytes4 functionSelector2 = bytes4(keccak256("depositIntoStrategyWithSignature(address,address,uint256,address,uint256,bytes)"));
        require(functionSelector == functionSelector2, "functionSelectors do not match");
        require(functionSelector == 0x32e89ace, "functionSelectors do not match");
    }
}
