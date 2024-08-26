// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IERC20Minter} from "../src/interfaces/IERC20Minter.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {ISenderCCIP} from "../src/interfaces/ISenderCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";
import {DeploySenderOnL2Script} from "../script/2_deploySenderOnL2.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";

// 6551 accounts
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ERC6551Registry} from "@6551/ERC6551Registry.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {EigenAgent6551TestUpgrade} from "./mocks/EigenAgent6551TestUpgrade.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";



contract CCIP_Eigen_CompleteWithdrawal_6551Tests is Test {

    DeployReceiverOnL1Script public deployReceiverOnL1Script;
    DeploySenderOnL2Script public deployOnL2Script;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    SignatureUtilsEIP1271 public signatureUtils;

    uint256 public deployerKey;
    address public deployer;
    uint256 public bobKey;
    address public bob;

    IReceiverCCIP public receiverContract;
    ISenderCCIP public senderContract;
    IRestakingConnector public restakingConnector;
    IERC20_CCIPBnM public erc20DripL1; // has drip faucet functions
    IERC20 public token;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    ProxyAdmin public proxyAdmin;

    uint256 l2ForkId;
    uint256 ethForkId;
    bool isTest;

    ERC6551Registry public registry;
    EigenAgentOwner721 public eigenAgentOwnerNft;
    IEigenAgent6551 public eigenAgent;

    // call params
    uint256 _expiry;
    uint256 _nonce;
    uint256 _amount;

    IStrategy[] public strategiesToWithdraw;
    uint256[] public sharesToWithdraw;


    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        vm.deal(deployer, 1 ether);

        bobKey = uint256(56789);
        bob = vm.addr(bobKey);
        vm.deal(bob, 1 ether);

        deployOnL2Script = new DeploySenderOnL2Script();
        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        signatureUtils = new SignatureUtilsEIP1271();

        isTest = block.chainid == 31337;
        l2ForkId = vm.createFork("basesepolia");        // 0
        ethForkId = vm.createSelectFork("ethsepolia"); // 1
        console.log("l2ForkId:", l2ForkId);
        console.log("ethForkId:", ethForkId);

        //////////////////////////////////////////////////////
        //// Setup L1 CCIP and Eigenlayer contracts
        //////////////////////////////////////////////////////
        (
            strategy,
            strategyManager,
            , // IStrategyFactory
            , // pauserRegistry
            delegationManager,
            , // rewardsCoordinator
            token
        ) = deployMockEigenlayerContractsScript.deployEigenlayerContracts(false);

        //// Setup L1 CCIP contracts and 6551 EigenAgent
        (receiverContract, restakingConnector) = deployReceiverOnL1Script.testrun();
        vm.deal(address(receiverContract), 1 ether);

        vm.startBroadcast(deployerKey);
        {
            //// allowlist deployer and mint initial balances
            receiverContract.allowlistSender(deployer, true);
            restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

            erc20DripL1 = IERC20_CCIPBnM(address(token));
            erc20DripL1.drip(address(receiverContract));
            erc20DripL1.drip(address(bob));

            /// Spawn EigenAgent for Bob
            eigenAgent = restakingConnector.spawnEigenAgentOnlyOwner(bob);
        }
        vm.stopBroadcast();


        /////////////////////////////////////////
        //// Setup L2 CCIP contracts
        /////////////////////////////////////////
        vm.selectFork(l2ForkId);
        senderContract = deployOnL2Script.testrun();
        vm.deal(address(senderContract), 1 ether);

        vm.startBroadcast(deployerKey);
        {
            // allow L2 sender contract to receive tokens back from L1
            senderContract.allowlistSourceChain(EthSepolia.ChainSelector, true);
            senderContract.allowlistSender(address(receiverContract), true);
            senderContract.allowlistSender(deployer, true);
            // fund L2 sender with CCIP-BnM tokens
            if (block.chainid == BaseSepolia.ChainId) {
                // drip() using CCIP's BnM faucet if forking from L2 Sepolia
                for (uint256 i = 0; i < 3; ++i) {
                    IERC20_CCIPBnM(BaseSepolia.CcipBnM).drip(address(senderContract));
                }
            }

        }
        vm.stopBroadcast();


        //////////////////////////////////////////////////////
        /// L1: ReceiverCCIP -> EigenAgent -> Eigenlayer
        //////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        _amount = 0.0133 ether;
        _expiry = block.timestamp + 1 days;

        vm.startBroadcast(bobKey);
        _nonce = eigenAgent.getExecNonce();
        vm.stopBroadcast();

        /////////////////////////////////////
        //// Queue Withdrawal with EigenAgent
        /////////////////////////////////////
        (
            bytes memory data,
            bytes32 digestHash,
            bytes memory signature
        ) = createEigenAgentDepositSignature(
            bobKey,
            _amount,
            _nonce,
            _expiry
        );
        signatureUtils.checkSignature_EIP1271(bob, digestHash, signature);

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        destTokenAmounts[0] = Client.EVMTokenAmount({
            token: address(token), // CCIP-BnM token address on Eth Sepolia.
            amount: _amount
        });
        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(0x0),
            sourceChainSelector: BaseSepolia.ChainSelector, // Arb Sepolia source chain selector
            sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
            destTokenAmounts: destTokenAmounts, // Tokens and their amounts in their destination chain representation.
            data: abi.encode(string(
                EigenlayerMsgEncoders.encodeDepositWithSignature6551Msg(
                    address(strategy),
                    address(token),
                    _amount,
                    bob, // original staker: looks up userToEigenAgent[staker] or spawns an EigenAgent
                    _expiry,
                    signature
                )
            )) // CCIP abi.encodes a string message when sending
        });

        vm.startBroadcast(deployerKey);
        receiverContract.mockCCIPReceive(any2EvmMessage);
        vm.stopBroadcast();

        /////////////////////////////////////
        //// Queue Withdrawal with EigenAgent
        /////////////////////////////////////

        vm.selectFork(ethForkId);
        vm.startBroadcast(bobKey);

        strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = _amount;

        {

            IDelegationManager.QueuedWithdrawalParams[] memory QWPArray;
            QWPArray = new IDelegationManager.QueuedWithdrawalParams[](1);
            QWPArray[0] =
                IDelegationManager.QueuedWithdrawalParams({
                    strategies: strategiesToWithdraw,
                    shares: sharesToWithdraw,
                    withdrawer: address(eigenAgent)
                });

            (
                bytes memory data2,
                bytes32 digestHash2,
                bytes memory signature2
            ) = createEigenAgentQueueWithdrawalsSignature(
                bobKey,
                _nonce,
                _expiry,
                QWPArray
            );
            signatureUtils.checkSignature_EIP1271(bob, digestHash2, signature2);

            // note: abi.encodePacked to join the payload + signature
            bytes memory dataWithSignature = abi.encodePacked(data2, _expiry, signature2);

            Client.Any2EVMMessage memory any2EvmMessageQueueWithdrawal = Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector, // Arb Sepolia source chain selector
                sender: abi.encode(address(deployer)), // bytes: abi.decode(sender) if coming from an EVM chain.
                destTokenAmounts: new Client.EVMTokenAmount[](0), // not bridging coins, just sending msg
                data: abi.encode(string(
                    dataWithSignature
                ))
            });

            receiverContract.mockCCIPReceive(any2EvmMessageQueueWithdrawal);
        }
       vm.stopBroadcast();

    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_CCIP_Eigenlayer_CompleteWithdrawal() public {

        /////////////////////////////////////////////////////////////////
        //// Complete Queued Withdrawals
        /////////////////////////////////////////////////////////////////

        vm.selectFork(ethForkId);
        vm.startBroadcast(bob);
        console.log("bob:", bob);

        uint32 startBlock = uint32(block.number);
        // uint256 withdrawalNonce = 0;
        uint256 withdrawalNonce = delegationManager.cumulativeWithdrawalsQueued(bob);

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager.Withdrawal({
            staker: address(eigenAgent),
            delegatedTo: delegationManager.delegatedTo(address(eigenAgent)),
            withdrawer: address(eigenAgent),
            nonce: withdrawalNonce,
            startBlock: startBlock,
            strategies: strategiesToWithdraw,
            shares: sharesToWithdraw
        });

        bytes32 withdrawalRoot = delegationManager.calculateWithdrawalRoot(withdrawal);
        require(withdrawalRoot != 0, "withdrawal root missing");

        IERC20[] memory tokensToWithdraw = new IERC20[](1);
        tokensToWithdraw[0] = strategiesToWithdraw[0].underlyingToken();

        vm.stopBroadcast();

        /////////////////////////////////////////////////////////////////
        //// 1. [L2] Send CompleteWithdrawals message to L2 Bridge
        /////////////////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);
        vm.startBroadcast(bob);

        address tokenDestination = BaseSepolia.CcipBnM; // CCIP-BnM L2 address
        uint256 stakerBalanceOnL2Before = IERC20(tokenDestination).balanceOf(bob);

        (
            bytes memory data,
            bytes32 digestHash,
            bytes memory signature
        ) = createEigenAgentCompleteWithdrawalSignature(
            bobKey,
            withdrawal,
            tokensToWithdraw,
            0, //middlewareTimesIndex,
            true // receiveAsTokens
        );
        signatureUtils.checkSignature_EIP1271(bob, digestHash, signature);

        bytes memory dataWithSignature = abi.encodePacked(data, _expiry, signature);
        console.log("sig1");
        console.logBytes(signature);

        senderContract.sendMessagePayNative(
            EthSepolia.ChainSelector, // destination chain
            address(receiverContract),
            string(dataWithSignature),
            address(tokenDestination),
            0 // not sending tokens, just message
        );
        vm.stopBroadcast();

        /////////////////////////////////////////////////////////////////
        //// [Offchain] CCIP relays tokens and message to L1 bridge
        /////////////////////////////////////////////////////////////////

        /////////////////////////////////////////////////////////////////
        //// 2. [L1] Mock receiving CompleteWithdrawals message on L1 Bridge
        /////////////////////////////////////////////////////////////////
        // need to fork ethsepolia to get: ReceiverCCIP -> Router calls to work
        vm.selectFork(ethForkId);
        vm.startBroadcast(address(receiverContract));

        vm.warp(block.timestamp + 120); // 120 seconds = 10 blocks (12second per block)
        vm.roll((block.timestamp + 120) / 12);

        uint256 _numWithdrawals = delegationManager.cumulativeWithdrawalsQueued(address(eigenAgent));
        require(_numWithdrawals > 0, "must queueWithdrawals first before completeWithdrawals");
        console.log("eigenAgent withdrawals queued:", _numWithdrawals);

        // mock L1 bridge receiving CCIP message and calling CompleteWithdrawal on Eigenlayer
        receiverContract.mockCCIPReceive(
            Client.Any2EVMMessage({
                messageId: bytes32(uint256(9999)),
                sourceChainSelector: BaseSepolia.ChainSelector,
                sender: abi.encode(deployer),
                data: abi.encode(string(
                    dataWithSignature
                )),
                destTokenAmounts: new Client.EVMTokenAmount[](0)
            })
        );
        // tokens in the ReceiverCCIP bridge contract
        console.log("balanceOf(receiverContract):", token.balanceOf(address(receiverContract)));
        vm.stopBroadcast();

        /////////////////////////////////////////////////////////////////
        //// [Offchain] CCIP relays tokens and message to L2 bridge
        /////////////////////////////////////////////////////////////////

        /////////////////////////////////////////////////////////////////
        //// 3. [L2] Mock receiving CompleteWithdrawals message from L1
        /////////////////////////////////////////////////////////////////
        vm.selectFork(l2ForkId);
        vm.startBroadcast(deployerKey);
        // Mock SenderContract on L2 receiving the tokens and TransferToAgentOwner CCIP message from L1
        senderContract.mockCCIPReceive(
            makeCCIPEigenlayerMsg_TransferToAgentOwner(withdrawalRoot, bob)
        );

        uint256 stakerBalanceOnL2After = IERC20(tokenDestination).balanceOf(address(bob));
        console.log("balanceOf(bob) on L2 before:", stakerBalanceOnL2Before);
        console.log("balanceOf(eigenAgent) on L2 after:", stakerBalanceOnL2After);

        require(
            (stakerBalanceOnL2Before + _amount) == stakerBalanceOnL2After,
            "balanceOf(bob) on L2 should increase by _amount after L2 -> L2 withdrawal"
        );

        vm.stopBroadcast();
    }

    /*
     *
     *
     *             Functions
     *
     *
     */

    function createEigenAgentQueueWithdrawalsSignature(
        uint256 signerKey,
        uint256 nonce,
        uint256 expiry,
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalsArray
    ) public view returns (bytes memory, bytes32, bytes memory) {

        bytes memory data = EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(
            queuedWithdrawalsArray
        );

        bytes32 digestHash = signatureUtils.createEigenAgentCallDigestHash(
            address(delegationManager), // target to call
            0 ether,
            data,
            nonce,
            block.chainid,
            expiry
        );

        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digestHash);
            signature = abi.encodePacked(r, s, v);
        }

        return (data, digestHash, signature);
    }

    function createEigenAgentDepositSignature(
        uint256 signerKey,
        uint256 amount,
        uint256 nonce,
        uint256 expiry
    ) public view returns (bytes memory, bytes32, bytes memory) {

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
            block.chainid,
            expiry
        );

        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digestHash);
            signature = abi.encodePacked(r, s, v);
        }

        return (data, digestHash, signature);
    }

    function createEigenAgentCompleteWithdrawalSignature(
        uint256 signerKey,
        IDelegationManager.Withdrawal memory withdrawal,
        IERC20[] memory tokensToWithdraw,
        uint256 middlewareTimesIndex,
        bool receiveAsTokens
    ) public view returns (bytes memory, bytes32, bytes memory) {

        bytes memory data = EigenlayerMsgEncoders.encodeCompleteWithdrawalMsg(
            withdrawal,
            tokensToWithdraw,
            middlewareTimesIndex,
            receiveAsTokens
        );

        bytes32 digestHash = signatureUtils.createEigenAgentCallDigestHash(
            address(delegationManager),
            0 ether,
            data,
            _nonce,
            EthSepolia.ChainId,
            _expiry
        );

        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digestHash);
            signature = abi.encodePacked(r, s, v);
        }

        return (data, digestHash, signature);
    }


    function makeCCIPEigenlayerMsg_TransferToAgentOwner(
        bytes32 withdrawalRoot,
        address agentOwner
    ) public view returns (Client.Any2EVMMessage memory) {

        // Not bridging tokens, just sending message to withdraw
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](0);

        Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
            messageId: bytes32(uint256(9999)),
            sourceChainSelector: EthSepolia.ChainSelector,
            sender: abi.encode(deployer),
            data: abi.encode(string(
                EigenlayerMsgEncoders.encodeHandleTransferToAgentOwnerMsg(
                    withdrawalRoot,
                    agentOwner
                )
            )), // CCIP abi.encodes a string message when sending
            destTokenAmounts: destTokenAmounts
        });

        return any2EvmMessage;
    }

}
