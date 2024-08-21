// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {IERC20Minter} from "../src/interfaces/IERC20Minter.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {FileReader} from "./FileReader.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";


contract WhitelistCCIPContractsScript is Script {

    IRestakingConnector public restakingConnector;
    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    FileReader public fileReader;

    uint256 public deployerKey;
    address public deployer;

    function run() public {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");
        console.log("block.chainid", block.chainid);

        fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        senderContract = fileReader.getSenderContract();
        (receiverContract, restakingConnector) = fileReader.getReceiverRestakingConnectorContracts();

        require(address(receiverContract) != address(0), "receiverContract cannot be 0");
        require(address(restakingConnector) != address(0), "restakingConnector cannot be 0");

        address tokenL1 = EthSepolia.CcipBnM;
        address tokenL2 = BaseSepolia.CcipBnM;

       //////////// L2 Sepolia ////////////
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);

        // allow L2 sender contract to send tokens to L1
        senderContract.allowlistSourceChain(BaseSepolia.ChainSelector, true);
        senderContract.allowlistSender(address(receiverContract), true);
        IERC20_CCIPBnM(tokenL2).drip(deployer);
        vm.stopBroadcast();


        //////////// Eth Sepolia ////////////
        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        receiverContract.allowlistSender(deployer, true);
        // Remember to fund L1 receiver with gas and tokens in production.

        if (block.chainid == 11155111) {
            // drip() using CCIP's BnM faucet if forking from ETH sepolia
            IERC20_CCIPBnM(tokenL1).drip(address(receiverContract));
            // each drip() gives you 1e18 coin
        } else {
            // mint() if we deployed our own Mock ERC20
            IERC20Minter(tokenL1).mint(address(receiverContract), 3 ether);
        }

        vm.stopBroadcast();
    }
}
