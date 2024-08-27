// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/Vm.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";
import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {ScriptUtils} from "./ScriptUtils.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";


contract DepositWithSignatureScript is Script, ScriptUtils {

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    IAgentFactory public agentFactory;
    address public senderAddr;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    IERC20 public token;
    IERC20 public ccipBnM;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    FileReader public fileReader; // keep outside vm.startBroadcast() to avoid deploying
    SignatureUtilsEIP1271 public signatureUtils;

    uint256 public deployerKey;
    address public deployer;

    function run() public {

        uint256 l2ForkId = vm.createSelectFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        signatureUtils = new SignatureUtilsEIP1271(); // needs ethForkId to call getDomainSeparator
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

        senderContract = fileReader.readSenderContract();
        senderAddr = address(senderContract);

        (
            receiverContract,
            restakingConnector
        ) = fileReader.readReceiverRestakingConnector();
        agentFactory = fileReader.readAgentFactory();

        ccipBnM = IERC20(address(BaseSepolia.CcipBnM)); // BaseSepolia contract
        token = IERC20(address(EthSepolia.BridgeToken)); // CCIPBnM on EthSepolia

        //////////////////////////////////////////////////////////
        /// Create message and signature
        /// In production this is done on the client/frontend
        //////////////////////////////////////////////////////////

        // First get EigenAgent from EthSepolia
        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        uint256 nonce = 0;
        /// ReceiverCCIP spawns an EigenAgent when CCIP message reaches L1
        /// if user does not already have an EigenAgent NFT on L1.  Nonce is then 0.
        IEigenAgent6551 eigenAgent = agentFactory.getEigenAgent(deployer);
        // IEigenAgent6551 eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);
        console.log("eigenAgent:", address(eigenAgent));
        if (address(eigenAgent) != address(0)) {
            // Otherwise if the user already has a EigenAgent, fetch current execution Nonce
            nonce = eigenAgent.getExecNonce();
        }

        uint256 amount = 0.00717 ether;
        uint256 expiry = block.timestamp + 3 hours;

        bytes memory data = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
            address(strategy),
            address(token),
            amount
        );

        bytes32 digestHash = signatureUtils.createEigenAgentCallDigestHash(
            address(strategyManager),
            0 ether,
            data,
            nonce,
            EthSepolia.ChainId, // destination chainid where EigenAgent lives
            expiry
        );

        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash);
            signature = abi.encodePacked(r, s, v);
        }



        bytes memory withdrawalMessage;
        bytes memory signatureEigenAgent;
        bytes memory messageWithSignature;

        // sign the message for EigenAgent to execute Eigenlayer command
        (
            signatureEigenAgent,
            messageWithSignature
        ) = signatureUtils.signMessageForEigenAgentExecution(
            deployerKey,
            address(delegationManager),
            withdrawalMessage,
            execNonce,
            expiry
        );

        signatureUtils.checkSignature_EIP1271(deployer, digestHash, signature);

        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        /// ReceiverCCIP -> EigenAgent -> Eigenlayer
        //////////////////////////////////////////////////////
        // Make sure we are on BaseSepolia Fork to make contract calls to CCIP-BnM
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);

        topupSenderEthBalance(senderAddr);

        // Check L2 CCIP-BnM ETH balances for gas
        if (ccipBnM.balanceOf(senderAddr) < 0.1 ether) {
            ccipBnM.approve(deployer, 0.1 ether);
            ccipBnM.transferFrom(deployer, senderAddr, 0.1 ether);
        }
        // Approve L2 senderContract to send ccip-BnM tokens to Router
        ccipBnM.approve(senderAddr, amount);

        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature),
            address(ccipBnM),
            amount
        );

        vm.stopBroadcast();
    }

}
