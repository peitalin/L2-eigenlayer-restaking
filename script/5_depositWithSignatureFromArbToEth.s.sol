// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/Vm.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStrategyManagerDomain} from "../src/interfaces/IStrategyManagerDomain.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {FileReader, ArbSepolia, EthSepolia} from "./Addresses.sol";
import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {ScriptUtils} from "./ScriptUtils.sol";


contract DepositWithSignatureFromArbToEthScript is Script, ScriptUtils {

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    address public senderAddr;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    IERC20 public token;
    IERC20 public token2;
    IERC20 public ccipBnM;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    FileReader public fileReader; // keep outside vm.startBroadcast() to avoid deploying
    SignatureUtilsEIP1271 public signatureUtils;
    EigenlayerMsgEncoders public eigenlayerMsgEncoders;

    uint256 public deployerKey;
    address public deployer;
    bool public payFeeWithETH = true;

    function run() public {

        require(block.chainid == 421614, "Must run script on Arbitrum network");

        uint256 arbForkId = vm.createFork("arbsepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");
        console.log("arbForkId:", arbForkId);
        console.log("ethForkId:", ethForkId);
        console.log("block.chainid", block.chainid);

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        signatureUtils = new SignatureUtilsEIP1271(); // needs ethForkId to call getDomainSeparator
        eigenlayerMsgEncoders = new EigenlayerMsgEncoders(); // needs ethForkId to call encodeDeposit
        fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        (
            strategy,
            strategyManager,
            , // strategyFactory
            , // pauserRegistry
            delegationManager,
            , // _rewardsCoordinator
            // token
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        senderContract = fileReader.getSenderContract();
        senderAddr = address(senderContract);

        (receiverContract, restakingConnector) = fileReader.getReceiverRestakingConnectorContracts();

        ccipBnM = IERC20(address(ArbSepolia.CcipBnM)); // ArbSepolia contract
        token = IERC20(address(EthSepolia.BridgeToken)); // CCIPBnM on EthSepolia

        //////////////////////////////////////////////////////////
        /// Create message and signature
        /// In production this is done on the client/frontend
        //////////////////////////////////////////////////////////

        // First get nonce from StrategyManager in EthSepolia
        vm.selectFork(ethForkId);
        uint256 nonce = IStrategyManagerDomain(address(strategyManager)).nonces(deployer);
        uint256 amount = 0.00515 ether; // bridging 0.00515 CCIPBnM
        uint256 expiry = block.timestamp + 12 hours;

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
        vm.selectFork(arbForkId);

        /////////////////////////////
        /// Begin Broadcast
        /////////////////////////////
        vm.startBroadcast(deployerKey);

        // Check L2 CCIP-BnM ETH balances for gas
        if (ccipBnM.balanceOf(senderAddr) < 0.1 ether) {
            ccipBnM.approve(deployer, 0.1 ether);
            ccipBnM.transferFrom(deployer, senderAddr, 0.1 ether);
        }
        // Approve L2 senderContract to send ccip-BnM tokens to Router
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

}
