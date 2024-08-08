// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, stdJson, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ISenderCCIP} from "../src/ISenderCCIP.sol";
import {IReceiverCCIP} from "../src/IReceiverCCIP.sol";
import {IRestakingConnector} from "../src/IRestakingConnector.sol";


contract FileReader is Script {

    function getSenderContract() public view returns (ISenderCCIP) {
        string memory filePath = "./broadcast/2_deployOnArb.s.sol/421614/run-latest.json";
        string memory broadcastData = vm.readFile(filePath);
        // Check transaction is the correct RestakingConnector deployment tx
        uint256 txNumber = _findCreateTx(broadcastData, "SenderCCIP");

        string memory contractAddr = string(abi.encodePacked(".transactions[", Strings.toString(txNumber), "].contractAddress"));
        address senderAddr = address(stdJson.readAddress(broadcastData, contractAddr));
        return ISenderCCIP(senderAddr);
    }

    function getReceiverRestakingConnectorContracts() public view returns (IReceiverCCIP, IRestakingConnector) {

        string memory broadcastData = vm.readFile("broadcast/3_deployOnEth.s.sol/11155111/run-latest.json");

        // Check transaction is the correct ReceiveCCIP deployment tx
        uint256 txNumber = _findCreateTx(broadcastData, "ReceiverCCIP");
        string memory contractAddr = string(abi.encodePacked(".transactions[", Strings.toString(txNumber), "].contractAddress"));
        IReceiverCCIP _receiverContract = IReceiverCCIP(address(stdJson.readAddress(broadcastData, contractAddr)));

        // Check transaction is the correct RestakingConnector deployment tx
        uint256 txNumber2 = _findCreateTx(broadcastData, "RestakingConnector");
        string memory contractAddr2 = string(abi.encodePacked(".transactions[", Strings.toString(txNumber2), "].contractAddress"));
        IRestakingConnector _restakingConnector = IRestakingConnector(address(stdJson.readAddress(broadcastData, contractAddr2)));

        return (_receiverContract, _restakingConnector);
    }

    function _findCreateTx(string memory broadcastData, string memory _contractName) internal pure returns (uint256) {
        for (uint256 i; i < 4; i++) {
            string memory contractName = stdJson.readString(broadcastData, string(abi.encodePacked(".transactions[", Strings.toString(i), "].contractName")));
            string memory transactionType = stdJson.readString(broadcastData, string(abi.encodePacked(".transactions[", Strings.toString(i), "].transactionType")));
            if (
                keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked(_contractName)) &&
                keccak256(abi.encodePacked(transactionType)) == keccak256(abi.encodePacked("CREATE"))
            ) {
                return i;
            }
        }
        console.log(_contractName);
        revert("CREATE deployment TX not found in <script>.s.sol/<chainid>/run-latest.json");
    }
}

library ArbSepolia {

    //////////////////////////////////////////////
    // Arb Sepolia
    //////////////////////////////////////////////
    // Router:
    // 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165
    //
    // chain selector:
    // 3478487238524512106
    //
    // CCIP-BnM token:
    // 0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D
    //////////////////////////////////////////////

    address constant Router = 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165;

    uint64 constant ChainSelector = 3478487238524512106;

    // The CCIP-BnM contract address at the source chain
    // https://docs.chain.link/ccip/supported-networks/v1_2_0/testnet#arbitrum-sepolia-ethereum-sepolia
    address constant CcipBnM = 0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D;

    address constant BridgeToken = CcipBnM ;

    address constant Link = 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E;

    uint256 constant ChainId = 421614;
}

library EthSepolia {
    //////////////////////////////////////////////
    // ETH Sepolia
    //////////////////////////////////////////////
    // Router:
    // 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59
    //
    // chain selector:
    // 16015286601757825753
    //
    // CCIP-BnM token:
    // 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05
    //////////////////////////////////////////////

    address constant Router = 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59;

    uint64 constant ChainSelector = 16015286601757825753;

    address constant CcipBnM = 0xFd57b4ddBf88a4e07fF4e34C487b99af2Fe82a05;

    address constant BridgeToken = CcipBnM ;

    address constant Link = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    uint256 constant ChainId = 11155111;
}