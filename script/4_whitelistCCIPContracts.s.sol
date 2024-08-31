// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {ISenderUtils} from "../src/interfaces/ISenderUtils.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {IERC20Minter} from "../src/interfaces/IERC20Minter.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {FileReader} from "./FileReader.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";


contract WhitelistCCIPContractsScript is Script {

    FileReader public fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying

    IRestakingConnector public restakingConnectorProxy;
    IAgentFactory public agentFactory;
    IReceiverCCIP public receiverProxy;
    ISenderCCIP public senderProxy;
    ISenderUtils public senderUtilsProxy;

    uint256 public deployerKey = vm.envUint("DEPLOYER_KEY");
    address public deployer = vm.addr(deployerKey);

    function run() public {

        senderProxy = fileReader.readSenderContract();
        senderUtilsProxy = fileReader.readSenderUtils();

        (
            receiverProxy,
            restakingConnectorProxy
        ) = fileReader.readReceiverRestakingConnector();

        agentFactory = fileReader.readAgentFactory();

        require(address(senderProxy) != address(0), "senderProxy cannot be 0");
        require(address(senderUtilsProxy) != address(0), "senderUtilsProxy cannot be 0");
        require(address(receiverProxy) != address(0), "receiverProxy cannot be 0");
        require(address(restakingConnectorProxy) != address(0), "restakingConnectorProxy cannot be 0");
        require(address(agentFactory) != address(0), "agentFactory cannot be 0");

        address tokenL1 = EthSepolia.BridgeToken;
        address tokenL2 = BaseSepolia.BridgeToken;

        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

       //////////// L2 Sepolia ////////////
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);

        // allow L2 sender contract to send tokens to L1
        senderProxy.allowlistSender(address(receiverProxy), true);
        senderProxy.allowlistSourceChain(BaseSepolia.ChainSelector, true);
        senderProxy.allowlistDestinationChain(EthSepolia.ChainSelector, true);

        // set GasLimits
        uint256[] memory gasLimits = new uint256[](7);
        gasLimits[0] = 2_200_000; // depositIntoStrategy            [gas: 1,935,006] 1.4mil to mint agent, 500k for deposit
        // https://sepolia.etherscan.io/tx/0xebcf428192d04fc02b1770c40feaa81429424ba6c42ac8bad6cbadb1c31b7c1c
        gasLimits[1] = 700_000; // depositIntoStrategyWithSignature [gas: ?]
        gasLimits[2] = 800_000; // queueWithdrawals                 [gas: 713_400]
        gasLimits[3] = 800_000; // completeWithdrawals              [gas: 645_948]
        gasLimits[4] = 600_000; // delegateTo                       [gas: ?]
        gasLimits[5] = 600_000; // delegateToBySignature            [gas: ?]
        gasLimits[6] = 400_000; // undelegate                       [gas: ?]

        bytes4[] memory functionSelectors = new bytes4[](7);
        functionSelectors[0] = 0xe7a050aa;
        // cast sig "depositIntoStrategy(address,address,uint256)" == 0xe7a050aa
        functionSelectors[1] = 0x32e89ace;
        // cast sig "depositIntoStrategyWithSignature()" == 0x32e89ace
        functionSelectors[2] = 0x0dd8dd02;
        // cast sig "queueWithdrawals((address[],uint256[],address)[])" == 0x0dd8dd02
        functionSelectors[3] = 0x60d7faed;
        // cast sig "completeQueuedWithdrawal((address,address,address,uint256,uint32,address[],uint256[]),address[],uint256,bool)" == 0x60d7faed
        functionSelectors[4] = 0xeea9064b;
        // cast sig "delegateTo(address,(bytes,uint256),bytes32)" == 0xeea9064b
        functionSelectors[5] = 0x7f548071;
        // cast sig "delegateToBySignature(address,address,(bytes,uint256),(bytes,uint256),bytes32)" == 0x7f548071
        functionSelectors[6] = 0xda8be864;
            // cast sig "undelegate(address)" == 0xda8be864

        senderUtilsProxy.setGasLimitsForFunctionSelectors(
            functionSelectors,
            gasLimits
        );

        uint256[] memory gasLimits_R = new uint256[](1);
        gasLimits_R[0] = 400_000; // handleTransferToAgentOwner       [gas: 268_420]

        bytes4[] memory functionSelectors_R = new bytes4[](8);
        functionSelectors_R[0] = 0xd8a85b48;
        // cast sig "handleTransferToAgentOwner(bytes)" == 0xd8a85b48

        restakingConnectorProxy.setGasLimitsForFunctionSelectors(
            functionSelectors_R,
            gasLimits_R
        );

        IERC20_CCIPBnM(tokenL2).drip(deployer);
        vm.stopBroadcast();

        //////////// Eth Sepolia ////////////
        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        receiverProxy.allowlistSender(address(senderProxy), true);
        receiverProxy.allowlistSourceChain(BaseSepolia.ChainSelector, true);
        receiverProxy.allowlistSourceChain(EthSepolia.ChainSelector, true);
        receiverProxy.allowlistDestinationChain(BaseSepolia.ChainSelector, true);
        // Remember to fund L1 receiver with gas and tokens in production.

        if (block.chainid == 11155111) {
            // drip() using CCIP's BnM faucet if forking from ETH sepolia
            IERC20_CCIPBnM(tokenL1).drip(address(receiverProxy));
            // each drip() gives you 1e18 coin
        } else {
            // mint() if we deployed our own Mock ERC20
            IERC20Minter(tokenL1).mint(address(receiverProxy), 3 ether);
        }

        vm.stopBroadcast();
    }
}
