// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/Vm.sol";

import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";
import {ScriptUtils} from "./ScriptUtils.sol";


contract DepositFromArbToEthScript is Script, ScriptUtils {

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    uint256 amountBridgedAndStaked;

    uint256 public deployerKey;
    address public deployer;


    function run() public {

        // calling CCIP-BnM address on sepolia
        vm.createSelectFork("basesepolia");

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        FileReader fileUtils = new FileReader();
        senderContract = fileUtils.getSenderContract();
        address senderAddr = address(senderContract);
        (receiverContract, restakingConnector) = fileUtils.getReceiverRestakingConnectorContracts();

        IERC20 ccipBnM = IERC20(BaseSepolia.CcipBnM);

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        // check CCIP-BnM balances for sender contract if it's a lock/unlock bridge model
        if (ccipBnM.balanceOf(senderAddr) < 0.1 ether) {
            // we're sending 0.001 CCIPBnM
            ccipBnM.approve(deployer, 0.1 ether);
            ccipBnM.transferFrom(deployer, senderAddr, 0.1 ether);
        }
        //// Approve senderContract to send ccip-BnM tokens
        amountBridgedAndStaked = 0.0023 ether;
        ccipBnM.approve(senderAddr, amountBridgedAndStaked);

        uint64 destinationChainSelector = EthSepolia.ChainSelector;

        // Note: fuctionSelector removed from SenderCCIP; use depositIntoStrategyWithSignature
        string memory message = string(abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategy(uint256,address)")),
            amountBridgedAndStaked,
            deployer
        ));

        topupSenderEthBalance(senderAddr);

        senderContract.sendMessagePayNative(
            destinationChainSelector,
            address(receiverContract),
            message,
            address(ccipBnM),
            amountBridgedAndStaked
        );

        vm.stopBroadcast();
    }

}
