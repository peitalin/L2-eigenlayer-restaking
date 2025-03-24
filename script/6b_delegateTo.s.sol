// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/Test.sol";
import {Client} from "@chainlink/ccip/libraries/Client.sol";
import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {ISignatureUtilsMixinTypes} from "@eigenlayer-contracts/interfaces/ISignatureUtilsMixin.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {BaseScript} from "./BaseScript.sol";
import {EthSepolia} from "./Addresses.sol";


contract DelegateToScript is BaseScript {

    uint256 deployerKey;
    address deployer;

    uint256 operatorKey;
    address operator;
    address staker;
    address TARGET_CONTRACT; // Contract that EigenAgent forwards calls to

    function run() public {
        return _run(false);
    }

    function mockrun() public {
        return _run(true);
    }

    function _run(bool isTest) private {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        readContractsAndSetupEnvironment(isTest, deployer);

        TARGET_CONTRACT = address(delegationManager);

        //////////////////////////////////////////////////////////
        // L1: Get Operator
        //////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        // operatorKey = vm.envUint("OPERATOR_KEY1");
        operatorKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        operator = vm.addr(operatorKey);

        //// Get User's EigenAgent
        IEigenAgent6551 eigenAgent = agentFactory.getEigenAgent(deployer);
        require(
            strategyManager.stakerDepositShares(address(eigenAgent), strategy) > 0,
            "EigenAgent has no deposit in Eigenlayer"
        );

        // if already delegated, must undelegate and wait 7 days first.
        require(!delegationManager.isDelegated(address(eigenAgent)), "EigenAgent is already actively delegated");

        uint256 execNonce = eigenAgent.execNonce();
        uint256 sigExpiry = block.timestamp + 1 hours;

        /////////////////////////////////////////////////////////////////
        /////// Broadcast DelegateTo message on L2
        /////////////////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);

        // Operator Approver signs the delegateTo call
        uint256 randomSalt = vm.randomUint();
        bytes32 approverSalt = bytes32(randomSalt);
        console.log("approverSalt: ");
        console.logBytes32(approverSalt);
        console.log("Operator address:", operator);

        ISignatureUtilsMixinTypes.SignatureWithExpiry memory approverSignatureAndExpiry;
        {
            bytes32 digestHash1 = calculateDelegationApprovalDigestHash(
                address(eigenAgent), // staker == msg.sender == eigenAgent from Eigenlayer's perspective
                operator, // operator
                operator, // _delegationApprover,
                approverSalt,
                sigExpiry,
                address(delegationManager), // delegationManagerAddr
                EthSepolia.ChainId
            );
            console.log("Operator digestHash:");
            console.logBytes32(digestHash1);

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorKey, digestHash1);
            bytes memory signature1 = abi.encodePacked(r, s, v);

            console.log("Operator signature:");
            console.logBytes(signature1);

            approverSignatureAndExpiry = ISignatureUtilsMixinTypes.SignatureWithExpiry({
                signature: signature1,
                expiry: sigExpiry
            });
        }

        // sign the message for EigenAgent to execute Eigenlayer command
        bytes memory messageWithSignature_DT = signMessageForEigenAgentExecution(
            deployerKey,
            address(eigenAgent),
            EthSepolia.ChainId, // destination chainid where EigenAgent lives
            TARGET_CONTRACT, // DelegationManager.delegateTo()
            encodeDelegateTo(
                operator,
                approverSignatureAndExpiry,
                approverSalt
            ),
            execNonce,
            sigExpiry
        );

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](0);

        uint256 gasLimit = senderHooks.getGasLimitForFunctionSelector(
            IDelegationManager.delegateTo.selector
        );
        uint256 routerFees = getRouterFeesL2(
            address(receiverContract),
            string(messageWithSignature_DT),
            tokenAmounts,
            gasLimit
        );

        vm.startBroadcast(deployerKey);

        senderContract.sendMessagePayNative{value: routerFees}(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(messageWithSignature_DT),
            tokenAmounts,
            gasLimit // use default gasLimit for this function
        );

        vm.stopBroadcast();

    }

}
