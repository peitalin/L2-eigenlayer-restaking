// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {FileReader, ArbSepolia, EthSepolia} from "./Addresses.sol";
import {DeployMockEigenlayerContractsScript} from "./1_deployMockEigenlayerContracts.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";


contract QueueWithdrawalWithSignatureScript is Script {

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    address public senderAddr;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    IERC20 public token;
    IERC20 public ccipBnM;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    FileReader public fileReader; // keep outside vm.startBroadcast() to avoid deploying
    SignatureUtilsEIP1271 public signatureUtils;
    EigenlayerMsgEncoders public eigenlayerMsgEncoders;

    uint256 public deployerKey;
    address public deployer;
    bool public payFeeWithETH = true;
    address public staker;
    uint256 public amount;
    uint256 public expiry;

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

        //////////////////////////////////////////////////////////
        /// Create message and signature
        /// In production this is done on the client/frontend
        //////////////////////////////////////////////////////////

        // First get nonce from Eigenlayer contracts in EthSepolia
        vm.selectFork(ethForkId);

        // TODO: refactor SenderCCIP to allow sending 0 tokens
        amount = 0.00001 ether; // only sending a withdrawal message, not bridging tokens.
        staker = deployer;
        expiry = block.timestamp + 6 hours;

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = strategyManager.stakerStrategyShares(staker, strategy);

        address withdrawer = address(receiverContract);
        uint256 stakerNonce = delegationManager.cumulativeWithdrawalsQueued(staker);
        uint32 startBlock = uint32(block.number); // needed to CompleteWithdrawals

        bytes32 digestHash = signatureUtils.calculateQueueWithdrawalDigestHash(
            staker,
            strategiesToWithdraw,
            sharesToWithdraw,
            stakerNonce,
            expiry,
            address(delegationManager),
            block.chainid
        );

        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash);
            signature = abi.encodePacked(r, s, v);
        }

        signatureUtils.checkSignature_EIP1271(staker, digestHash, signature);

        /////////////////////////////////////////////////////////////////
        ////// Setup Queue Withdrawals Params (reads from Eigenlayer contracts on L1)
        /////////////////////////////////////////////////////////////////

        // Note: This test needs the queueWithdrawalWithSignature feature:
        // https://github.com/Layr-Labs/eigenlayer-contracts/pull/676

        IDelegationManager.QueuedWithdrawalWithSignatureParams memory queuedWithdrawalWithSig;
        queuedWithdrawalWithSig = IDelegationManager.QueuedWithdrawalWithSignatureParams({
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw,
            withdrawer: withdrawer,
            staker: staker,
            signature: signature,
            expiry: expiry
        });

        IDelegationManager.QueuedWithdrawalWithSignatureParams[] memory queuedWithdrawalWithSigArray;
        queuedWithdrawalWithSigArray = new IDelegationManager.QueuedWithdrawalWithSignatureParams[](1);
        queuedWithdrawalWithSigArray[0] = queuedWithdrawalWithSig;

        bytes memory message = eigenlayerMsgEncoders.encodeQueueWithdrawalsWithSignatureMsg(
            queuedWithdrawalWithSigArray
        );

        bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(
            IDelegationManager.Withdrawal({
                staker: staker,
                delegatedTo: delegationManager.delegatedTo(staker),
                withdrawer: withdrawer,
                nonce: stakerNonce,
                startBlock: startBlock,
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw
            })
        );

        /////////////////////////////////////////////////////////////////
        /////// Broadcast to Arb L2
        /////////////////////////////////////////////////////////////////

        vm.selectFork(arbForkId);
        vm.startBroadcast(deployerKey);

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

        saveWithdrawalRoot(
            staker,
            withdrawer,
            stakerNonce,
            startBlock,
            strategiesToWithdraw,
            sharesToWithdraw,
            withdrawalRoot
        );
    }

    function saveWithdrawalRoot(
        address _staker,
        address _withdrawer,
        uint256 _nonce,
        uint256 _startBlock,
        IStrategy[] memory _strategies,
        uint256[] memory _shares,
        bytes32 withdrawalRoot
    ) public {

        // { "inputs": <inputs_data>}
        /////////////////////////////////////////////////
        string memory inputs_key = "inputs";
        vm.serializeAddress(inputs_key , "staker", _staker);
        vm.serializeAddress(inputs_key , "withdrawer", _withdrawer);
        vm.serializeUint(inputs_key , "nonce", _nonce);
        vm.serializeUint(inputs_key , "startBlock", _startBlock);
        vm.serializeAddress(inputs_key , "strategy", address(_strategies[0]));
        string memory inputs_data = vm.serializeUint(inputs_key , "shares", _shares[0]);
        // figure out how to serialize arrays

        /////////////////////////////////////////////////
        // { "outputs": <outputs_data>}
        /////////////////////////////////////////////////
        string memory outputs_key = "outputs";
        string memory outputs_data = vm.serializeBytes32(outputs_key, "withdrawalRoot", withdrawalRoot);

        /////////////////////////////////////////////////
        // { "chainInfo": <chain_info_data>}
        /////////////////////////////////////////////////
        string memory chainInfo_key = "chainInfo";
        vm.serializeUint(chainInfo_key, "block", block.number);
        vm.serializeUint(chainInfo_key, "timestamp", block.timestamp);
        vm.serializeUint(chainInfo_key, "destinationChain", ArbSepolia.ChainId);
        string memory chainInfo_data = vm.serializeUint(chainInfo_key, "sourceChain", EthSepolia.ChainId);

        /////////////////////////////////////////////////
        // combine objects to a root object
        /////////////////////////////////////////////////
        string memory root_object = "rootObject";
        vm.serializeString(root_object, chainInfo_key, chainInfo_data);
        vm.serializeString(root_object, outputs_key, outputs_data);
        string memory finalJson = vm.serializeString(root_object, inputs_key, inputs_data);

        string memory stakerAddress = Strings.toHexString(uint160(staker), 20);

        // mkdir for user if need be.
        string[] memory mkdirForUser = new string[](2);
        mkdirForUser[0] = "mkdir";
        mkdirForUser[1] = string(abi.encodePacked("script/withdrawals/", stakerAddress));
        bytes memory res = vm.ffi(mkdirForUser);

        string memory finalOutputPath = string(abi.encodePacked(
            "script/withdrawals/",
            stakerAddress,
            "/run-",
            Strings.toString(block.timestamp),
            ".json"
        ));
        string memory finalOutputPathLatest = string(abi.encodePacked(
            "script/withdrawals/",
            stakerAddress,
             "/run-latest.json"
        ));
        console.log("finaloutputPath", finalOutputPath);
        console.log("finaloutputPathLatest", finalOutputPathLatest);

        vm.writeJson(finalJson, finalOutputPath);
        vm.writeJson(finalJson, finalOutputPathLatest);
    }

    function topupSenderEthBalance(address _senderAddr) public {
        if (_senderAddr.balance < 0.05 ether) {
            (bool sent, ) = address(_senderAddr).call{value: 0.1 ether}("");
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
