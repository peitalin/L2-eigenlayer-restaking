// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/Vm.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategyManagerDomain} from "../src/IStrategyManagerDomain.sol";

import {IReceiverCCIP} from "../src/IReceiverCCIP.sol";
import {SenderCCIP} from "../src/SenderCCIP.sol";
import {IRestakingConnector} from "../src/IRestakingConnector.sol";

import {FileUtils} from "./FileUtils.sol";
import {ArbSepolia, EthSepolia} from "./Constants.sol";
import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";


contract DepositWithSignatureFromArbToEthScript is Script {

    IReceiverCCIP public receiverContract;
    SenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    address public senderAddr;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    IERC20 public token;
    IERC20 public token2;
    IERC20 public ccipBnM;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    FileUtils public fileUtils; // keep outside vm.startBroadcast() to avoid deploying
    SignatureUtilsEIP1271 public signatureUtils;
    EigenlayerMsgEncoders public eigenlayerMsgEncoders;

    uint256 public deployerKey;
    address public deployer;
    bool public payFeeWithETH = true;

    function run() public {

        require(block.chainid == 421614, "Must run script on Arbitrum network");

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        // Fork to get nonce from StrategyManager in EthSepolia
        vm.createSelectFork("ethsepolia"); // forkId: 1

        signatureUtils = new SignatureUtilsEIP1271();
        eigenlayerMsgEncoders = new EigenlayerMsgEncoders();
        fileUtils = new FileUtils(); // keep outside vm.startBroadcast() to avoid deploying
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        (
            strategyManager,
            ,
            ,
            delegationManager,
            strategy
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        senderContract = fileUtils.getSenderContract();
        senderAddr = address(senderContract);

        (receiverContract, restakingConnector) = fileUtils.getReceiverRestakingConnectorContracts();

        ccipBnM = IERC20(address(ArbSepolia.CcipBnM)); // ArbSepolia contract
        token = IERC20(address(EthSepolia.BridgeToken)); // CCIPBnM on EthSepolia

        /////////////////////////////
        /// Create message and signature
        /////////////////////////////
        uint256 amount = 0.00515 ether; // bridging 0.00515 CCIPBnM
        uint256 expiry = block.timestamp + 1 days;
        uint256 nonce = IStrategyManagerDomain(address(strategyManager)).nonces(deployer);
        bytes32 domainSeparator = signatureUtils.getDomainSeparator(address(strategyManager), EthSepolia.ChainId);
        bytes32 digestHash = signatureUtils.createEigenlayerDepositDigest(
            strategy,
            token,
            amount,
            deployer,
            nonce,
            expiry, // expiry
            domainSeparator
        );
        // generate ECDSA signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        signatureUtils.checkSignature_EIP1271(deployer, digestHash, signature);

        bytes memory message = eigenlayerMsgEncoders.encodeDepositIntoStrategyWithSignatureMsg(
            address(strategy),
            address(token),
            amount,
            deployer,
            expiry,
            signature
        );

        //// Make sure we are on ArbSepolia Fork to make contract calls to CCIP-BnM
        vm.createSelectFork("arbsepolia"); // forkId: 2;

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        // Check L2 CCIP-BnM ETH balances for gas
        if (ccipBnM.balanceOf(senderAddr) < 0.1 ether) {
            ccipBnM.approve(deployer, 0.1 ether);
            ccipBnM.transferFrom(deployer, senderAddr, 0.1 ether);
        }
        // Approve L2 senderContract to send ccip-BnM tokens
        ccipBnM.approve(senderAddr, amount);

        if (payFeeWithETH) {
            topupSenderEthBalance(senderAddr);

            senderContract.sendMessagePayNative(
                EthSepolia.ChainSelector, // destination chain
                address(receiverContract),
                string(message),
                address(ccipBnM),
                amount
            );
        } else {
            topupSenderLINKBalance(senderAddr, deployer);

            senderContract.sendMessagePayLINK(
                EthSepolia.ChainSelector, // destination chain
                address(receiverContract),
                string(message),
                address(ccipBnM),
                amount
            );
        }

        vm.stopBroadcast();
    }

    function topupSenderEthBalance(address _senderAddr) public {
        if (_senderAddr.balance < 0.02 ether) {
            (bool sent, ) = address(_senderAddr).call{value: 0.05 ether}("");
            require(sent, "Failed to send Ether");
        }
    }

    function topupSenderLINKBalance(address _senderAddr, address deployerAddr) public {
        /// Only if using sendMessagePayLINK()
        IERC20 linkTokenOnArb = IERC20(ArbSepolia.Link);
        // check LINK balances for sender contract
        uint256 senderLinkBalance = linkTokenOnArb.balanceOf(_senderAddr);

        if (senderLinkBalance < 2 ether) {
            linkTokenOnArb.approve(deployerAddr, 2 ether);
            linkTokenOnArb.transferFrom(deployerAddr, senderAddr, 2 ether);
        }
        //// Approve senderContract to send LINK tokens for fees
        linkTokenOnArb.approve(address(senderContract), 2 ether);
    }

}
