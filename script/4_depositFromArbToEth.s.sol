// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/Vm.sol";

import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {IReceiverCCIP} from "../src/IReceiverCCIP.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {IRestakingConnector} from "../src/IRestakingConnector.sol";
import {FileUtils} from "./FileUtils.sol";


contract DepositFromArbToEthScript is Script {

    IReceiverCCIP public receiverContract;
    SenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    uint256 amountBridgedAndStaked;

    uint256 public deployerKey;
    address public deployer;


    function run() public {

        require(block.chainid == 421614, "Must run script on Arbitrum network");

        bool payFeeWithETH = true;

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        FileUtils fileUtils = new FileUtils();
        senderContract = fileUtils.getSenderContract();
        address senderAddr = address(senderContract);
        (receiverContract, restakingConnector) = fileUtils.getReceiverRestakingConnectorContracts();

        // The CCIP-BnM contract address at the source chain
        // https://docs.chain.link/ccip/supported-networks/v1_2_0/testnet#arbitrum-sepolia-ethereum-sepolia
        IERC20 ccipBnM = IERC20(0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D);

        vm.startBroadcast(deployerKey);

        // check CCIP-BnM balances for sender contract if it's a lock/unlock bridge model
        if (ccipBnM.balanceOf(senderAddr) < 0.1 ether) {
            // we're sending 0.001 CCIPBnM
            ccipBnM.approve(deployer, 0.1 ether);
            ccipBnM.transferFrom(deployer, senderAddr, 0.1 ether);
        }
        //// Approve senderContract to send ccip-BnM tokens
        amountBridgedAndStaked = 0.0093 ether;
        ccipBnM.approve(senderAddr, amountBridgedAndStaked);

        //// L2 -> L1 token transfer + message passing
        uint64 destinationChainSelector = 16015286601757825753; // Ethereum Sepolia
        // cast calldata "depositIntoStrategy(uint256,address)" 2 0x8454d149Beb26E3E3FC5eD1C87Fb0B2a1b7B6c2c
        // 0xf7e784ef00000000000000000000000000000000000000000000000000000000000000020000000000000000000000008454d149beb26e3e3fc5ed1c87fb0b2a1b7b6c2c
        string memory message = string(abi.encodeWithSelector(
            bytes4(keccak256("depositIntoStrategy(uint256,address)")),
            amountBridgedAndStaked,
            deployer
        ));
        // abi.encodeWithSelector(bytes4(keccak256("depositIntoStrategy(IStrategy,IERC20,uint256)")), 10, 10);
        // strategyManager.depositIntoStrategy(
        //     IStrategy(address(mockMagicStrategy)),
        //     IERC20(address(mockMagic)),
        //     AMOUNT_TO_DEPOSIT
        // );

        if (payFeeWithETH) {

            topupSenderEthBalance(senderAddr);

            senderContract.sendMessagePayNative(
                destinationChainSelector,
                address(receiverContract),
                message,
                address(ccipBnM),
                amountBridgedAndStaked
            );
        } else {

            topupSenderLINKBalance(senderAddr, deployer);

            senderContract.sendMessagePayLINK(
                destinationChainSelector,
                address(receiverContract),
                message,
                address(ccipBnM),
                amountBridgedAndStaked
            );
        }

        vm.stopBroadcast();
    }

    function topupSenderEthBalance(address senderAddr) public {
        if (senderAddr.balance < 0.02 ether) {
            (bool sent, ) = address(senderAddr).call{value: 0.05 ether}("");
            require(sent, "Failed to send Ether");
        }
    }

    function topupSenderLINKBalance(address senderAddr, address deployerAddr) public {
        /// Only if using sendMessagePayLINK()
        address linkAddressOnArb = address(0xb1D4538B4571d411F07960EF2838Ce337FE1E80E);
        IERC20 linkTokenOnArb = IERC20(linkAddressOnArb);

        // check LINK balances for sender contract
        uint256 senderLinkBalance = linkTokenOnArb.balanceOf(senderAddr);

        if (senderLinkBalance < 2 ether) {
            linkTokenOnArb.approve(deployerAddr, 2 ether);
            linkTokenOnArb.transferFrom(deployerAddr, senderAddr, 2 ether);
        }

        //// Approve senderContract to send LINK tokens for fees
        linkTokenOnArb.approve(address(senderContract), 2 ether);
    }
}
