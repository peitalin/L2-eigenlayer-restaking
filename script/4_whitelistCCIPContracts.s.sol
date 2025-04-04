// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {IBurnMintERC20} from "@chainlink/shared/token/ERC20/IBurnMintERC20.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderHooks} from "../src/interfaces/ISenderHooks.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";

import {GasLimits} from "./GasLimits.sol";
import {FileReader} from "./FileReader.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";


contract WhitelistCCIPContractsScript is Script, FileReader, GasLimits {

    IRestakingConnector public restakingConnectorProxy;
    IAgentFactory public agentFactoryProxy;
    IReceiverCCIP public receiverProxy;
    ISenderCCIP public senderProxy;
    ISenderHooks public senderHooksProxy;

    function run() public {
        return _run(false);
    }

    function mockrun() public {
        return _run(true);
    }

    function _run(bool isTest) private {

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerKey);

        senderProxy = readSenderContract();
        senderHooksProxy = readSenderHooks();

        (
            receiverProxy,
            restakingConnectorProxy
        ) = readReceiverRestakingConnector();

        agentFactoryProxy = readAgentFactory();

        (
            IEigenAgentOwner721 eigenAgentOwner721,
            IERC6551Registry registry6551
        ) = readEigenAgent721AndRegistry();

        require(address(senderProxy) != address(0), "senderProxy cannot be 0");
        require(address(senderHooksProxy) != address(0), "senderHooksProxy cannot be 0");
        require(address(receiverProxy) != address(0), "receiverProxy cannot be 0");
        require(address(restakingConnectorProxy) != address(0), "restakingConnectorProxy cannot be 0");
        require(address(agentFactoryProxy) != address(0), "agentFactory cannot be 0");

        address tokenL2 = BaseSepolia.BridgeToken;

        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

        /////////////////////////////////////////////
        //////////// Setup L2 SenderCCIP ////////////
        /////////////////////////////////////////////
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);

        // allow L1 receiver contract to send tokens back to L2 for withdrawals and reward claims
        senderProxy.allowlistSender(EthSepolia.ChainSelector, address(receiverProxy), true);
        senderProxy.allowlistSourceChain(BaseSepolia.ChainSelector, true);
        senderProxy.allowlistDestinationChain(EthSepolia.ChainSelector, true);

        (
            bytes4[] memory functionSelectors,
            uint256[] memory gasLimits
        ) = getGasLimits();

        senderHooksProxy.setGasLimitsForFunctionSelectors(
            functionSelectors,
            gasLimits
        );

        senderHooksProxy.setSenderCCIP(address(senderProxy));

        if (isTest) {
            IBurnMintERC20(tokenL2).mint(deployer, 1 ether);
        }

        vm.stopBroadcast();

        require(
            address(senderProxy.getSenderHooks()) != address(0),
            "senderProxy: missing senderHooks"
        );
        require(
            senderProxy.allowlistedSenders(EthSepolia.ChainSelector, address(receiverProxy)),
            "senderProxy: must allowlistSender(receiverProxy) on EthSepolia"
        );
        require(
            senderProxy.allowlistedSourceChains(EthSepolia.ChainSelector),
            "senderProxy: must allowlist SourceChain: EthSepolia"
        );
        require(
            senderProxy.allowlistedDestinationChains(EthSepolia.ChainSelector),
            "senderProxy: must allowlist DestinationChain: EthSepolia)"
        );

        ///////////////////////////////////////////////
        //////////// Setup L1 ReceiverCCIP ////////////
        ///////////////////////////////////////////////
        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        // allow L2 sender contract to send tokens to L1 for deposits
        receiverProxy.allowlistSender(BaseSepolia.ChainSelector, address(senderProxy), true);
        receiverProxy.allowlistSourceChain(BaseSepolia.ChainSelector, true);
        receiverProxy.allowlistSourceChain(EthSepolia.ChainSelector, true);
        receiverProxy.allowlistDestinationChain(BaseSepolia.ChainSelector, true);
        // allow L1 receiver to send tokens back to L2 for withdrawals and reward claims

        // Remember to fund L1 receiver with gas and tokens in production.
        // seed the receiver contract with a bit of ETH
        if (address(receiverProxy).balance < 0.01 ether) {
            (bool sent, ) = address(receiverProxy).call{value: 0.02 ether}("");
            require(sent, "Failed to send Ether");
        }

        uint256[] memory gasLimits_R = new uint256[](1);
        gasLimits_R[0] = 300_000; // handleTransferToAgentOwner [gas: 261,029]

        bytes4[] memory functionSelectors_R = new bytes4[](1);
        functionSelectors_R[0] = 0xd8a85b48;
        // cast sig "handleTransferToAgentOwner(bytes)" == 0xd8a85b48

        restakingConnectorProxy.setGasLimitsForFunctionSelectors(
            functionSelectors_R,
            gasLimits_R
        );

        vm.stopBroadcast();

        require(
            receiverProxy.allowlistedSenders(BaseSepolia.ChainSelector, address(senderProxy)),
            "receiverProxy: must allowlistSender(senderProxy) on BaseSepolia"
        );
        require(
            address(agentFactoryProxy.getRestakingConnector()) == address(restakingConnectorProxy),
            "agentFactoryProxy: missing restakingConnector"
        );
        require(
            address(receiverProxy.getRestakingConnector()) == address(restakingConnectorProxy),
            "receiverProxy: missing restakingConnector"
        );
        require(
            address(restakingConnectorProxy.getAgentFactory()) == address(agentFactoryProxy),
            "restakingConnector: missing AgentFactory"
        );
        require(
            address(restakingConnectorProxy.getReceiverCCIP()) == address(receiverProxy),
            "restakingConnector: missing ReceiverCCIP"
        );
        require(
            address(eigenAgentOwner721.getAgentFactory()) == address(agentFactoryProxy),
            "EigenAgentOwner721 NFT: missing AgentFactory"
        );
        require(
            address(agentFactoryProxy.getRestakingConnector()) == address(restakingConnectorProxy),
            "agentFactory: missing restakingConnector"
        );
        require(
            address(agentFactoryProxy.erc6551Registry()) == address(registry6551),
            "agentFactory: missing erc6551registry"
        );
    }
}

