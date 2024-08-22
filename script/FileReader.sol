// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, stdJson, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {EthSepolia, BaseSepolia} from "./Addresses.sol";

contract FileReader is Script {

    /// @dev hardcoded chainid for contracts. Update for prod
    function getSenderContract() public view returns (ISenderCCIP) {

        string memory filePath = "./broadcast/2_deployOnL2.s.sol/84532/run-latest.json";
        string memory broadcastData = vm.readFile(filePath);
        // Check transaction is the correct RestakingConnector deployment tx
        uint256 txNumber = _findCreateTx(broadcastData, "TransparentUpgradeableProxy", 5);
        // TransparentUpgradeableProxy -> SenderCCIP

        string memory contractAddr = string(abi.encodePacked(".transactions[", Strings.toString(txNumber), "].contractAddress"));
        address senderAddr = address(stdJson.readAddress(broadcastData, contractAddr));
        return ISenderCCIP(senderAddr);
    }

    /// @dev hardcoded chainid for contracts. Update for prod
    function getSenderUtils() public view returns (address) {

        string memory filePath = "./broadcast/2_deployOnL2.s.sol/84532/run-latest.json";
        string memory broadcastData = vm.readFile(filePath);
        // Check transaction is the correct RestakingConnector deployment tx
        uint256 txNumber = _findCreateTx(broadcastData, "SenderUtils", 5);

        string memory contractAddr = string(abi.encodePacked(".transactions[", Strings.toString(txNumber), "].contractAddress"));
        address senderUtils = address(stdJson.readAddress(broadcastData, contractAddr));
        return senderUtils;
    }

    /// @dev hardcoded chainid for contracts. Update for prod
    function getL2ProxyAdmin() public view returns (address) {
        string memory broadcastData = vm.readFile("./broadcast/2_deployOnL2.s.sol/84532/run-latest.json");
        // Check transaction is the correct RestakingConnector deployment tx
        uint256 txNumber = _findCreateTx(broadcastData, "ProxyAdmin", 5);

        string memory contractAddr = string(abi.encodePacked(".transactions[", Strings.toString(txNumber), "].contractAddress"));
        address proxyAdmin = address(stdJson.readAddress(broadcastData, contractAddr));
        return proxyAdmin;
    }

    /// @dev hardcoded chainid for contracts. Update for prod
    function getL1ProxyAdmin() public view returns (address) {
        string memory broadcastData = vm.readFile("broadcast/3_deployOnEth.s.sol/11155111/run-latest.json");
        // Check transaction is the correct RestakingConnector deployment tx
        uint256 txNumber = _findCreateTx(broadcastData, "ProxyAdmin", 12);

        string memory contractAddr = string(abi.encodePacked(".transactions[", Strings.toString(txNumber), "].contractAddress"));
        address proxyAdmin = address(stdJson.readAddress(broadcastData, contractAddr));
        return proxyAdmin;
    }

    /// @dev hardcoded chainid for eigenlayer contracts. Update for prod
    function getReceiverRestakingConnectorContracts() public view returns (IReceiverCCIP, IRestakingConnector) {
        string memory broadcastData = vm.readFile("broadcast/3_deployOnEth.s.sol/11155111/run-latest.json");

        // Check transaction is the correct ReceiverCCIP deployment tx
        uint256 txNumber = _findCreateTx(broadcastData, "TransparentUpgradeableProxy", 12);
        // TransparentUpgradeableProxy -> ReceiverCCIP
        string memory contractAddr = string(abi.encodePacked(".transactions[", Strings.toString(txNumber), "].contractAddress"));
        IReceiverCCIP _receiverContract = IReceiverCCIP(address(stdJson.readAddress(broadcastData, contractAddr)));

        // Check transaction is the correct RestakingConnector deployment tx
        uint256 txNumber2 = _findCreateTx(broadcastData, "RestakingConnector", 12);
        string memory contractAddr2 = string(abi.encodePacked(".transactions[", Strings.toString(txNumber2), "].contractAddress"));
        IRestakingConnector _restakingConnector = IRestakingConnector(address(stdJson.readAddress(broadcastData, contractAddr2)));

        return (_receiverContract, _restakingConnector);
    }

    function _findCreateTx(string memory broadcastData, string memory _contractName, uint256 len) internal pure returns (uint256) {
        for (uint256 i; i < len; i++) {
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

    /////////////////////////////////////////////////
    // Withdrawals
    /////////////////////////////////////////////////

    function saveWithdrawalInfo(
        address _staker,
        address _delegatedTo,
        address _withdrawer,
        uint256 _nonce,
        uint256 _startBlock,
        IStrategy[] memory _strategies,
        uint256[] memory _shares,
        bytes32 _withdrawalRoot,
        string memory _filePath
    ) public {

        // { "inputs": <inputs_data>}
        /////////////////////////////////////////////////
        vm.serializeAddress("inputs" , "staker", _staker);
        vm.serializeAddress("inputs" , "delegatedTo", _delegatedTo);
        vm.serializeAddress("inputs" , "withdrawer", _withdrawer);
        vm.serializeUint("inputs" , "nonce", _nonce);
        vm.serializeUint("inputs" , "startBlock", _startBlock);
        vm.serializeAddress("inputs" , "strategy", address(_strategies[0]));
        string memory inputs_data = vm.serializeUint("inputs" , "shares", _shares[0]);
        // figure out how to serialize arrays

        /////////////////////////////////////////////////
        // { "outputs": <outputs_data>}
        /////////////////////////////////////////////////
        string memory outputs_data = vm.serializeBytes32("outputs", "withdrawalRoot", _withdrawalRoot);

        /////////////////////////////////////////////////
        // { "chainInfo": <chain_info_data>}
        /////////////////////////////////////////////////
        vm.serializeUint("chainInfo", "block", block.number);
        vm.serializeUint("chainInfo", "timestamp", block.timestamp);
        vm.serializeUint("chainInfo", "destinationChain", BaseSepolia.ChainId);
        string memory chainInfo_data = vm.serializeUint("chainInfo", "sourceChain", EthSepolia.ChainId);

        /////////////////////////////////////////////////
        // combine objects to a root object
        /////////////////////////////////////////////////
        vm.serializeString("rootObject", "chainInfo", chainInfo_data);
        vm.serializeString("rootObject", "outputs", outputs_data);
        string memory finalJson = vm.serializeString("rootObject", "inputs", inputs_data);

        {
            string memory stakerAddress = Strings.toHexString(uint160(_staker), 20);
            // mkdir for user if need be.
            string[] memory mkdirForUser = new string[](3);
            mkdirForUser[0] = "mkdir";
            mkdirForUser[1] = "-p";
            mkdirForUser[2] = string(abi.encodePacked(_filePath, stakerAddress));
            vm.ffi(mkdirForUser);

            string memory finalOutputPath = string(abi.encodePacked(
                _filePath,
                stakerAddress,
                "/run-",
                Strings.toString(block.timestamp),
                ".json"
            ));
            string memory finalOutputPathLatest = string(abi.encodePacked(
                _filePath,
                stakerAddress,
                "/run-latest.json"
            ));

            vm.writeJson(finalJson, finalOutputPath);
            vm.writeJson(finalJson, finalOutputPathLatest);
        }
    }


    function readWithdrawalInfo(
        address stakerAddress,
        string memory filePath
    ) public view returns (IDelegationManager.Withdrawal memory) {

        string memory withdrawalData = vm.readFile(
            string(abi.encodePacked(
                filePath,
                Strings.toHexString(uint160(stakerAddress), 20),
                "/run-latest.json"
            ))
        );
        uint256 _nonce = stdJson.readUint(withdrawalData, ".inputs.nonce");
        uint256 _shares = stdJson.readUint(withdrawalData, ".inputs.shares");
        address _staker = stdJson.readAddress(withdrawalData, ".inputs.staker");
        address _strategy = stdJson.readAddress(withdrawalData, ".inputs.strategy");
        address _withdrawer = stdJson.readAddress(withdrawalData, ".inputs.withdrawer");
        address _delegatedTo = stdJson.readAddress(withdrawalData, ".inputs.delegatedTo");
        ///// NOTE: Wrong withdrawalRoot because the written startBlock is wrong
        ///// (written when bridging is initiated), instead of written after bridging is complete
        uint32 _startBlock = uint32(stdJson.readUint(withdrawalData, ".inputs.startBlock"));
        // bytes32 _withdrawalRoot = stdJson.readBytes32(withdrawalData, ".outputs.withdrawalRoot");

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);

        strategiesToWithdraw[0] = IStrategy(_strategy);
        sharesToWithdraw[0] = _shares;

        return (
            IDelegationManager.Withdrawal({
                staker: _staker,
                delegatedTo: _delegatedTo,
                withdrawer: _withdrawer,
                nonce: _nonce,
                startBlock: _startBlock,
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw
            })
        );
    }
}
