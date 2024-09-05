// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";
import "forge-std/Vm.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";
import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";
import {ScriptUtils} from "./ScriptUtils.sol";
import {ClientEncoders} from "./ClientEncoders.sol";
import {ClientSigners} from "./ClientSigners.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";


contract DepositAndMintEigenAgentScript is
    Script,
    ScriptUtils,
    FileReader,
    ClientEncoders,
    ClientSigners
{

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    IAgentFactory public agentFactory;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    IERC20 public tokenL1;
    IERC20 public tokenL2;

    uint256 public deployerKey;
    address public deployer;

    IEigenAgent6551 public eigenAgent;
    address public TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

    function run() public {
        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        return _run(false);
    }

    function mockrun(uint256 mockKey) public {
        deployerKey = mockKey;
        deployer = vm.addr(deployerKey);
        vm.deal(deployer, 1 ether);
        return _run(true);
    }

    function _run(bool isTest) public {

        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

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

        senderContract = readSenderContract();

        (
            receiverContract,
            restakingConnector
        ) = readReceiverRestakingConnector();
        agentFactory = readAgentFactory();

        tokenL1 = IERC20(address(EthSepolia.BridgeToken)); // CCIP-BnM on EthSepolia
        tokenL2 = IERC20(address(BaseSepolia.BridgeToken)); // CCIP-BnM on BaseSepolia

        TARGET_CONTRACT = address(strategyManager);


        //////////////////////////////////////////////////////////
        /// L1: Get Deposit Inputs
        //////////////////////////////////////////////////////////

        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        eigenAgent = agentFactory.getEigenAgent(deployer);
        require(
            address(eigenAgent) == address(0),
            "depositAndMintEigenAgent script: user already has an EigenAgent"
        );
        /// agentFactory will spawn an EigenAgent after bridging automatically
        /// if user does not already have an EigenAgent NFT on L1.
        /// but this costs more gas to be sent up-front for CCIP
        /// Nonce is then 0.
        uint256 execNonce = 0;
        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        /// L2: Dispatch Call
        //////////////////////////////////////////////////////
        // Make sure we are on BaseSepolia Fork
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);

        uint256 amount = 0.0619 ether;
        uint256 expiry = block.timestamp + 3 hours;
        bytes memory depositMessage;
        bytes memory messageWithSignature;

        {
            depositMessage = encodeDepositIntoStrategyMsg(
                address(strategy),
                address(tokenL1),
                amount
            );

            // sign the message for EigenAgent to execute Eigenlayer command
            messageWithSignature = signMessageForEigenAgentExecution(
                deployerKey,
                EthSepolia.ChainId, // destination chainid where EigenAgent lives
                TARGET_CONTRACT, // StrategyManager is the target
                depositMessage,
                execNonce,
                expiry
            );
        }

        // Check L2 CCIP-BnM balances
        if (tokenL2.balanceOf(deployer) < 1 ether) {
            IERC20_CCIPBnM(address(tokenL2)).drip(deployer);
            IERC20_CCIPBnM(address(tokenL2)).drip(address(senderContract));
        }

        topupSenderEthBalance(address(senderContract), isTest);

        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature),
            address(tokenL2),
            amount,
            0 // use default gasLimit (2,100,000 for deposit + mint EigenAgent)
        );

        vm.stopBroadcast();
    }
}
