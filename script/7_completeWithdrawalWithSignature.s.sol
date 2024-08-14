// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Script, stdJson, console} from "forge-std/Script.sol";
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


contract CompleteWithdrawalWithSignatureScript is Script {

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
    uint256 public middlewareTimesIndex; // not used yet, for slashing
    bool public receiveAsTokens;

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

        vm.selectFork(ethForkId);

        // TODO: refactor SenderCCIP to allow sending 0 tokens
        amount = 0.00001 ether; // only sending a withdrawal message, not bridging tokens.
        staker = deployer;
        expiry = block.timestamp + 6 hours;

        (
            IDelegationManager.Withdrawal memory withdrawal,
            bytes32 withdrawalRoot
        ) = readWithdrawalRoot(staker);

        // bytes32 digestHash = signatureUtils.calculateQueueWithdrawalDigestHash(
        //     staker,
        //     strategiesToWithdraw,
        //     sharesToWithdraw,
        //     stakerNonce,
        //     expiry,
        //     address(delegationManager),
        //     block.chainid
        // );
        // bytes memory signature;
        // {
        //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash);
        //     signature = abi.encodePacked(r, s, v);
        // }
        // signatureUtils.checkSignature_EIP1271(staker, digestHash, signature);

        bytes32 withdrawalRoot2 = delegationManager.calculateWithdrawalRoot(withdrawal);

        bytes32 targetWithdrawalRoot = hex"6473944b7edb8a41daccbc19b8ab074ea4adf188fa4163e0459d26af1ffba472";
        // https://sepolia.etherscan.io/tx/0x20baf6809a2dc7120f4ad81b1df6c1e876b47cc6deb88800ef538d1cb3803bf2

        console.log("withdrawalRoot:");
        console.logBytes32(withdrawalRoot);
        console.log("");
        console.log("withdrawalRoot2:");
        console.logBytes32(withdrawalRoot2);
        console.log("");
        console.log("targetWithdrawalRoot:");
        console.logBytes32(targetWithdrawalRoot);

        require(
            targetWithdrawalRoot == withdrawalRoot,
            "withdrawalRoots do not match"
        );

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = withdrawal.strategies[0].underlyingToken();

        /////////////////////////////////////////////////////////////////
        ////// Setup Complete Withdrawals Params
        /////////////////////////////////////////////////////////////////
        middlewareTimesIndex = 0; // not used yet, for slashing
        receiveAsTokens = true;

        // send CCIP message to CompleteWithdrawal
        bytes memory message = eigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
            withdrawal,
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
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
    }


    function readWithdrawalRoot(
        address stakerAddress
    ) public returns (IDelegationManager.Withdrawal memory, bytes32) {

        string memory withdrawalData = vm.readFile(
            string(abi.encodePacked(
                "script/withdrawals/",
                Strings.toHexString(uint160(stakerAddress), 20),
                "/run-latest.json"
            ))
        );
        uint256 _nonce = stdJson.readUint(withdrawalData, ".inputs.nonce");
        uint256 _shares = stdJson.readUint(withdrawalData, ".inputs.shares");
        address _staker = stdJson.readAddress(withdrawalData, ".inputs.staker");
        uint32 _startBlock = uint32(stdJson.readUint(withdrawalData, ".inputs.startBlock"));
        address _strategy = stdJson.readAddress(withdrawalData, ".inputs.strategy");
        address _withdrawer = stdJson.readAddress(withdrawalData, ".inputs.withdrawer");
        bytes32 _withdrawalRoot = stdJson.readBytes32(withdrawalData, ".outputs.withdrawalRoot");

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        uint256[] memory sharesToWithdraw = new uint256[](1);

        strategiesToWithdraw[0] = IStrategy(_strategy);
        sharesToWithdraw[0] = _shares;

        return (
            IDelegationManager.Withdrawal({
                staker: _staker,
                delegatedTo: delegationManager.delegatedTo(_staker),
                withdrawer: _withdrawer,
                nonce: _nonce,
                startBlock: _startBlock,
                strategies: strategiesToWithdraw,
                shares: sharesToWithdraw
            }),
            _withdrawalRoot
        );
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
