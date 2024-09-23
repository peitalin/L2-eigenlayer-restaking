// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, stdJson} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {EthSepolia, BaseSepolia} from "./Addresses.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";


contract FileReader is Script {

    string public FILEPATH_BRIDGE_CONTRACTS_L1 = "script/ethsepolia/bridgeContractsL1.config.json";
    string public FILEPATH_BRIDGE_CONTRACTS_L2 = "script/basesepolia/bridgeContractsL2.config.json";

    /////////////////////////////////////////////////
    // L2 Contracts
    /////////////////////////////////////////////////

    function readSenderContract() public view returns (ISenderCCIP) {
        string memory addrData;
        addrData = vm.readFile(FILEPATH_BRIDGE_CONTRACTS_L2);
        address senderAddr = stdJson.readAddress(addrData, ".contracts.senderCCIP");
        return ISenderCCIP(senderAddr);
    }

    function readSenderHooks() public view returns (ISenderHooks) {
        string memory addrData;
        addrData = vm.readFile(FILEPATH_BRIDGE_CONTRACTS_L2);
        address senderHooksAddr = stdJson.readAddress(addrData, ".contracts.senderHooks");
        return ISenderHooks(senderHooksAddr);
    }

    function readProxyAdminL2() public view returns (address) {
        string memory addrData;
        addrData = vm.readFile(FILEPATH_BRIDGE_CONTRACTS_L2);
        address proxyAdminL2Addr = stdJson.readAddress(addrData, ".contracts.proxyAdminL2");
        return proxyAdminL2Addr;
    }

    /// @dev hardcoded chainid for contracts. Update for prod
    function saveSenderBridgeContracts(
        address senderCCIP,
        address senderHooks,
        address proxyAdminL2,
        string memory filePath
    ) public {
        // { "inputs": <inputs_data>}
        /////////////////////////////////////////////////
        vm.serializeAddress("contracts" , "senderCCIP", senderCCIP);
        vm.serializeAddress("contracts" , "senderHooks", senderHooks);
        string memory inputs_data = vm.serializeAddress("contracts" , "proxyAdminL2", proxyAdminL2);

        /////////////////////////////////////////////////
        // { "chainInfo": <chain_info_data>}
        /////////////////////////////////////////////////
        vm.serializeUint("chainInfo", "block", block.number);
        vm.serializeUint("chainInfo", "timestamp", block.timestamp);
        string memory chainInfo_data = vm.serializeUint("chainInfo", "chainid", block.chainid);

        /////////////////////////////////////////////////
        // combine objects to a root object
        /////////////////////////////////////////////////
        vm.serializeString("rootObject", "chainInfo", chainInfo_data);
        string memory finalJson2 = vm.serializeString("rootObject", "contracts", inputs_data);

        // chains[31337] = "localhost";
        // chains[17000] = "holesky";
        // chains[84532] = "basesepolia";
        // chains[11155111] = "ethsepolia";
        string memory finalOutputPath2 = string(abi.encodePacked(
            filePath
        ));
        vm.writeJson(finalJson2, finalOutputPath2);
    }

    /////////////////////////////////////////////////
    // L1 Contracts
    /////////////////////////////////////////////////

    function readReceiverRestakingConnector() public view returns (IReceiverCCIP, IRestakingConnector) {
        string memory addrData;
        addrData = vm.readFile(FILEPATH_BRIDGE_CONTRACTS_L1);
        address receiverAddr = stdJson.readAddress(addrData, ".contracts.receiverCCIP");
        address restakingConnectorAddr = stdJson.readAddress(addrData, ".contracts.restakingConnector");
        return (
            IReceiverCCIP(receiverAddr),
            IRestakingConnector(restakingConnectorAddr)
        );
    }

    function readAgentFactory() public view returns (IAgentFactory) {
        string memory addrData;
        addrData = vm.readFile(FILEPATH_BRIDGE_CONTRACTS_L1);
        address agentFactoryAddr = stdJson.readAddress(addrData, ".contracts.agentFactory");
        return IAgentFactory(agentFactoryAddr);
    }

    function readBaseEigenAgent() public view returns (address) {
        string memory addrData;
        addrData = vm.readFile(FILEPATH_BRIDGE_CONTRACTS_L1);
        address baseEigenAgentAddr = stdJson.readAddress(addrData, ".contracts.baseEigenAgent");
        return baseEigenAgentAddr;
    }

    function readEigenAgent721AndRegistry() public view returns (IEigenAgentOwner721, IERC6551Registry) {
        string memory addrData;
        addrData = vm.readFile(FILEPATH_BRIDGE_CONTRACTS_L1);
        address eigenAgentOwner721 = stdJson.readAddress(addrData, ".contracts.eigenAgentOwner721");
        address registry6551 = stdJson.readAddress(addrData, ".contracts.registry6551");
        return (
            IEigenAgentOwner721(eigenAgentOwner721),
            IERC6551Registry(registry6551)
        );
    }

    function readProxyAdminL1() public view returns (address) {
        string memory addrData;
        addrData = vm.readFile(FILEPATH_BRIDGE_CONTRACTS_L1);
        address proxyAdminL1Addr = stdJson.readAddress(addrData, ".contracts.proxyAdminL1");
        return proxyAdminL1Addr;
    }

    function saveReceiverBridgeContracts(
        address receiverCCIP,
        address restakingConnector,
        address agentFactory,
        address registry6551,
        address eigenAgentOwner721,
        address baseEigenAgent,
        address proxyAdminL1,
        string memory filePath
    ) public {

        require(receiverCCIP != address(0), "receiverCCIP cannot be null");
        require(restakingConnector != address(0), "restakingConnector cannot be null");
        require(agentFactory != address(0), "agentFactory cannot be null");
        require(registry6551 != address(0), "registry6551 cannot be null");
        require(eigenAgentOwner721 != address(0), "eigenAgentOwner721 cannot be null");
        require(baseEigenAgent != address(0), "baseEigenAgent cannot be null");
        require(proxyAdminL1 != address(0), "proxyAdminL1 cannot be null");

        // { "inputs": <inputs_data>}
        /////////////////////////////////////////////////
        vm.serializeAddress("contracts" , "receiverCCIP", receiverCCIP);
        vm.serializeAddress("contracts" , "restakingConnector", restakingConnector);
        vm.serializeAddress("contracts" , "agentFactory", agentFactory);
        vm.serializeAddress("contracts" , "registry6551", registry6551);
        vm.serializeAddress("contracts" , "eigenAgentOwner721", eigenAgentOwner721);
        vm.serializeAddress("contracts" , "baseEigenAgent", baseEigenAgent);
        string memory inputs_data = vm.serializeAddress("contracts" , "proxyAdminL1", proxyAdminL1);

        /////////////////////////////////////////////////
        // { "chainInfo": <chain_info_data>}
        /////////////////////////////////////////////////
        vm.serializeUint("chainInfo", "block", block.number);
        vm.serializeUint("chainInfo", "timestamp", block.timestamp);
        string memory chainInfo_data = vm.serializeUint("chainInfo", "chainid", block.chainid);

        /////////////////////////////////////////////////
        // combine objects to a root object
        /////////////////////////////////////////////////
        vm.serializeString("rootObject", "chainInfo", chainInfo_data);
        string memory finalJson1 = vm.serializeString("rootObject", "contracts", inputs_data);

        // chains[31337] = "localhost";
        // chains[17000] = "holesky";
        // chains[84532] = "basesepolia";
        // chains[11155111] = "ethsepolia";
        string memory finalOutputPath1 = string(abi.encodePacked(
            filePath
        ));
        vm.writeJson(finalJson1, finalOutputPath1);
    }

    /////////////////////////////////////////////////
    // Withdrawal Roots
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
        bytes32 _withdrawalTransferRoot,
        string memory _filePath
    ) public {

        require(_staker != address(0), "staker cannot be null");
        require(_withdrawer != address(0), "withdrawer cannot be null");
        require(address(_strategies[0]) != address(0), "strategies[0] cannot be null");

        // { "inputs": <inputs_data>}
        /////////////////////////////////////////////////
        vm.serializeAddress("inputs" , "staker", _staker);
        vm.serializeAddress("inputs" , "delegatedTo", _delegatedTo);
        vm.serializeAddress("inputs" , "withdrawer", _withdrawer);
        vm.serializeUint("inputs" , "nonce", _nonce);
        vm.serializeUint("inputs" , "startBlock", _startBlock);
        vm.serializeAddress("inputs" , "strategy", address(_strategies[0]));
        string memory inputs_data = vm.serializeUint("inputs" , "shares", _shares[0]);

        /////////////////////////////////////////////////
        // { "outputs": <outputs_data>}
        /////////////////////////////////////////////////
        vm.serializeBytes32("outputs", "withdrawalTransferRoot", _withdrawalTransferRoot);
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
        ///// Note: Wrong startBlock produces wrong withdrawalRoots.
        ///// (startBlock is during withdrawal on L1), not when first sending message on L2
        uint32 _startBlock = uint32(stdJson.readUint(withdrawalData, ".inputs.startBlock"));
        // bytes32 _withdrawalRoot = stdJson.readBytes32(withdrawalData, ".outputs.withdrawalRoot");
        // bytes32 _withdrawalTransferRoot = stdJson.readBytes32(withdrawalData, ".outputs.withdrawalTransferRoot");

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

    function test_ignore_filereader() private {}
}
