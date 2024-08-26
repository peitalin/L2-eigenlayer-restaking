// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, stdJson, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureUtils} from "eigenlayer-contracts/src/contracts/interfaces/ISignatureUtils.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {BaseSepolia, EthSepolia} from "./Addresses.sol";
import {FileReader} from "./FileReader.sol";
import {ScriptUtils} from "./ScriptUtils.sol";
import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";


contract DelegateToScript is Script, ScriptUtils {

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    IDelegationManager public delegationManager;
    IERC20 public ccipBnM;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    FileReader public fileReader; // keep outside vm.startBroadcast() to avoid deploying
    SignatureUtilsEIP1271 public signatureUtils;

    uint256 public deployerKey;
    address public deployer;
    uint256 public operatorKey;
    address public operator;
    address public staker;

    function run() public {

        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        signatureUtils = new SignatureUtilsEIP1271(); // needs ethForkId to call getDomainSeparator
        fileReader = new FileReader(); // keep outside vm.startBroadcast() to avoid deploying
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();

        (
            , // strategy
            , // strategyManager,
            , // strategyFactory
            , // pauserRegistry
            delegationManager,
            , // _rewardsCoordinator
              // token
        ) = deployMockEigenlayerContractsScript.readSavedEigenlayerAddresses();

        senderContract = fileReader.readSenderContract();
        (receiverContract, restakingConnector) = fileReader.readReceiverRestakingConnector();
        ccipBnM = IERC20(address(BaseSepolia.CcipBnM)); // BaseSepolia contract

        //////////////////////////////////////////////////////////
        /// Create message and signature
        //////////////////////////////////////////////////////////

        vm.selectFork(ethForkId);

        //////////////////////////////////////////////////////////
        // Register Operator
        //////////////////////////////////////////////////////////

        operatorKey = vm.envUint("OPERATOR_KEY");
        operator = vm.addr(operatorKey);

        if (!delegationManager.isOperator(operator)) {

            vm.startBroadcast(deployerKey);
            topupSenderEthBalance(operator);
            vm.stopBroadcast();

            vm.startBroadcast(operatorKey);
            {
                IDelegationManager.OperatorDetails memory registeringOperatorDetails =
                    IDelegationManager.OperatorDetails({
                        __deprecated_earningsReceiver: vm.addr(0xb0b),
                        delegationApprover: operator,
                        stakerOptOutWindowBlocks: 4
                    });

                string memory metadataURI = "some operator";
                delegationManager.registerAsOperator(registeringOperatorDetails, metadataURI);

            }
            vm.stopBroadcast();
        }

        //////////////////////////////////////////////////////////
        // DelegateTo
        //////////////////////////////////////////////////////////

        ISignatureUtils.SignatureWithExpiry memory stakerSignatureAndExpiry;
        ISignatureUtils.SignatureWithExpiry memory approverSignatureAndExpiry;

        bytes32 approverSalt = bytes32(uint256(24)); // generate some random number/salt

        bytes memory signature1;
        bytes memory signature2;
        {
            uint256 sig1_expiry = block.timestamp + 1 hours;
            uint256 sig2_expiry = block.timestamp + 2 hours;

            bytes32 digestHash1 = signatureUtils.calculateStakerDelegationDigestHash(
                staker,
                0,  // nonce
                operator,
                sig1_expiry,
                address(delegationManager),
                EthSepolia.ChainId
            );
            bytes32 digestHash2 = signatureUtils.calculateDelegationApprovalDigestHash(
                staker,
                operator,
                operator, // _delegationApprover,
                approverSalt,
                sig2_expiry,
                address(delegationManager), // delegationManagerAddr
                EthSepolia.ChainId
            );

            (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(deployerKey, digestHash1);
            signature1 = abi.encodePacked(r1, s1, v1);
            stakerSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature1,
                expiry: sig1_expiry
            });

            (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(operatorKey, digestHash2);
            signature2 = abi.encodePacked(r2, s2, v2);
            approverSignatureAndExpiry = ISignatureUtils.SignatureWithExpiry({
                signature: signature2,
                expiry: sig2_expiry
            });
        }

        // send CCIP message to CompleteWithdrawal
        bytes memory message = EigenlayerMsgEncoders.encodeDelegateToBySignature(
            staker,
            operator,
            stakerSignatureAndExpiry,
            approverSignatureAndExpiry,
            approverSalt
        );

        /////////////////////////////////////////////////////////////////
        /////// Broadcast to L2
        /////////////////////////////////////////////////////////////////

        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);

        topupSenderEthBalance(address(senderContract));
        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(message),
            address(ccipBnM),
            0 // not bridging, just sending message
        );

        vm.stopBroadcast();

    }

}
