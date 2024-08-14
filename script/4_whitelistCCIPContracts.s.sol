// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {IERC20Minter} from "../src/interfaces/IERC20Minter.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {FileReader} from "./Addresses.sol";
import {ArbSepolia, EthSepolia} from "./Addresses.sol";


contract WhitelistCCIPContractsScript is Script {

    IRestakingConnector public restakingConnector;
    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    FileReader public fileReader;

    uint256 public deployerKey;
    address public deployer;

    function run() public returns (IReceiverCCIP, IRestakingConnector) {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        uint256 arbForkId = vm.createFork("arbsepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");
        console.log("arbForkId:", arbForkId);
        console.log("ethForkId:", ethForkId);
        console.log("block.chainid", block.chainid);

        fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        senderContract = fileReader.getSenderContract();
        (receiverContract, restakingConnector) = fileReader.getReceiverRestakingConnectorContracts();

        address tokenL1 = EthSepolia.CcipBnM;
        address tokenL2 = ArbSepolia.CcipBnM;

       //////////// Arb Sepolia ////////////
        vm.selectFork(arbForkId);
        vm.startBroadcast(deployerKey);

        // allow L1 sender contract to send tokens back to L2
        senderContract.allowlistSourceChain(EthSepolia.ChainSelector, true);
        senderContract.allowlistSender(address(receiverContract), true);

        vm.stopBroadcast();
        /////////////////////////////////////


        //////////// Eth Sepolia ////////////
        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        receiverContract.allowlistSender(deployer, true);

        // Remember to fund L1 receiver with gas and tokens in production.

        if (block.chainid == 11155111) {
            // drip() using CCIP's BnM faucet if forking from ETH sepolia
            for (uint256 i = 0; i < 3; ++i) {
                IERC20_CCIPBnM(tokenL1).drip(address(receiverContract));
                // each drip() gives you 1e18 coin
            }
            IERC20_CCIPBnM(tokenL1).balanceOf(address(receiverContract));
        } else {
            // mint() if we deployed our own Mock ERC20
            IERC20Minter(tokenL1).mint(address(receiverContract), 3 ether);
        }

        vm.stopBroadcast();
        /////////////////////////////////////
    }
}
