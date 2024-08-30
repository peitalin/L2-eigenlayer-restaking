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
import {ClientEncoders} from "./ClientEncoders.sol";
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
    ClientEncoders public encoders;
    SignatureUtilsEIP1271 public signatureUtils;

    uint256 public deployerKey;
    address public deployer;
    IEigenAgent6551 public eigenAgent;
    address public TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

    function run() public {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

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

        TARGET_CONTRACT = address(strategyManager);

        //////////////////////////////////////////////////////////
        /// L1: Get Deposit Inputs
        //////////////////////////////////////////////////////////

        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        uint256 execNonce = 0;
        /// ReceiverCCIP spawns an EigenAgent when CCIP message reaches L1
        /// if user does not already have an EigenAgent NFT on L1.  Nonce is then 0.
        eigenAgent = agentFactory.getEigenAgent(deployer);
        if (address(eigenAgent) != address(0)) {
            // if the user already has a EigenAgent, fetch current execution Nonce
            execNonce = eigenAgent.getExecNonce();
        } else {
            // otherwise agentFactory will spawn one for the user after bridging.
            ///// For testing only:
            // eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);
        }
        console.log("eigenAgent:", address(eigenAgent));
        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        /// L2: Dispatch Call
        //////////////////////////////////////////////////////
        // Make sure we are on BaseSepolia Fork
        vm.selectFork(l2ForkId);
        encoders = new ClientEncoders();
        signatureUtils = new SignatureUtilsEIP1271();

        vm.startBroadcast(deployerKey);

        uint256 amount = 0.00333 ether;
        uint256 expiry = block.timestamp + 3 hours;
        bytes memory depositMessage;
        bytes memory messageWithSignature;
        {
            depositMessage = encoders.encodeDepositIntoStrategyMsg(
                address(strategy),
                address(token),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signatureUtils.signMessageForEigenAgentExecution(
                deployerKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                TARGET_CONTRACT, // StrategyManager is the target
                depositMessage,
                execNonce,
                expiry
            );
        }

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
