// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, stdJson, console} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";

import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IReceiverCCIP} from "../src/IReceiverCCIP.sol";
import {IRestakingConnector} from "../src/IRestakingConnector.sol";


contract FileUtils is Test {

    function getSenderContract() public view returns (SenderCCIP) {
        string memory filePath = "./broadcast/2_deployOnArb.s.sol/421614/run-latest.json";
        string memory broadcastData = vm.readFile(filePath);
        address senderAddr = address(stdJson.readAddress(broadcastData, ".transactions[0].contractAddress"));
        return SenderCCIP(payable(senderAddr));
    }

    function getReceiverRestakingConnectorContracts() public view returns (IReceiverCCIP, IRestakingConnector) {

        string memory deploymentDataR = vm.readFile("broadcast/3_deployOnEth.s.sol/11155111/run-latest.json");

        // Check transaction is the correct ReceiveCCIP deployment tx
        uint256 txNumber = findCreateTx(deploymentDataR, "ReceiveCCIP");
        string memory contractAddr = string(abi.encodePacked(".transactions[", Strings.toString(txNumber), "].contractAddress"));
        IReceiverCCIP _receiverContract = IReceiverCCIP(address(stdJson.readAddress(deploymentDataR, contractAddr)));

        // Check transaction is the correct RestakingConnector deployment tx
        uint256 txNumber2 = findCreateTx(deploymentDataR, "RestakingConnector");
        string memory contractAddr2 = string(abi.encodePacked(".transactions[", Strings.toString(txNumber2), "].contractAddress"));
        IRestakingConnector _restakingConnector = IRestakingConnector(address(stdJson.readAddress(deploymentDataR, contractAddr2)));

        return (_receiverContract, _restakingConnector);
    }

    function findCreateTx(string memory deploymentDataR, string memory _contractName) public pure returns (uint256) {
        for (uint256 i; i < 4; i++) {
            string memory contractName = stdJson.readString(deploymentDataR, string(abi.encodePacked(".transactions[", Strings.toString(i), "].contractName")));
            string memory transactionType = stdJson.readString(deploymentDataR, string(abi.encodePacked(".transactions[", Strings.toString(i), "].transactionType")));
            if (
                keccak256(abi.encodePacked(contractName)) == keccak256(abi.encodePacked(_contractName)) &&
                keccak256(abi.encodePacked(transactionType)) == keccak256(abi.encodePacked("CREATE"))
            ) {
                return i;
            }
        }
        revert("CREATE deployment TX not found in 3_deployOnEth.s.sol/1155111/run-latest.json");
    }

}
