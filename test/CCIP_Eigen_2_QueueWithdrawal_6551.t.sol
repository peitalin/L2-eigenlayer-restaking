// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";

// 6551 accounts
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ERC6551Registry} from "@6551/ERC6551Registry.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {EigenAgent6551TestUpgrade} from "./mocks/EigenAgent6551TestUpgrade.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";



contract CCIP_Eigen_QueueWithdrawal_6551Tests is Test {

    DeployReceiverOnL1Script public deployReceiverOnL1Script;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    SignatureUtilsEIP1271 public signatureUtils;

    uint256 public deployerKey;
    address public deployer;
    uint256 public bobKey;
    address public bob;

    IReceiverCCIP public receiverContract;
    IRestakingConnector public restakingConnector;
    IERC20_CCIPBnM public erc20Drip; // has drip faucet functions
    IERC20 public token;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    ProxyAdmin public proxyAdmin;

    IAgentFactory public agentFactory;
    EigenAgentOwner721 public eigenAgentOwnerNft;

    // call params
    uint256 _expiry;
    uint256 _nonce;
    uint256 _amount;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        bobKey = uint256(56789);
        bob = vm.addr(bobKey);
        vm.deal(bob, 1 ether);

        deployReceiverOnL1Script = new DeployReceiverOnL1Script();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        signatureUtils = new SignatureUtilsEIP1271();

        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

        //// Configure Eigenlayer contracts
        (
            strategy,
            strategyManager,
            , // IStrategyFactory
            , // pauserRegistry
            delegationManager,
            , // rewardsCoordinator
            token
        ) = deployMockEigenlayerContractsScript.deployEigenlayerContracts(false);

        //// Configure CCIP contracts and 6551 EigenAgent
        (
            receiverContract,
            restakingConnector,
            agentFactory
        ) = deployReceiverOnL1Script.testrun();

        //// allowlist deployer and mint initial balances
        vm.startBroadcast(deployerKey);

        receiverContract.allowlistSender(deployer, true);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);

        erc20Drip = IERC20_CCIPBnM(address(token));
        erc20Drip.drip(address(receiverContract));
        erc20Drip.drip(address(bob));
        vm.stopBroadcast();

        _amount = 0.0028 ether;
        _expiry = block.timestamp + 1 days;
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_CCIP_Eigenlayer_QueueWithdrawal6551() public {

        vm.startBroadcast(deployerKey);
        IEigenAgent6551 eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(bob);
        vm.stopBroadcast();

        vm.startBroadcast(bobKey);
        _nonce = eigenAgent.getExecNonce();
        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        /// ReceiverCCIP -> EigenAgent -> Eigenlayer
        //////////////////////////////////////////////////////
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
                    bob,
                    _expiry,
                    signature
                )
            )) // CCIP abi.encodes a string message when sending
        });

        /////////////////////////////////////
        //// Mock send message to CCIP -> EigenAgent -> Eigenlayer
        /////////////////////////////////////
        vm.startBroadcast(deployerKey);
        receiverContract.mockCCIPReceive(any2EvmMessage);
        vm.stopBroadcast();


        vm.startBroadcast(bobKey);

        IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
        strategiesToWithdraw[0] = strategy;

        uint256[] memory sharesToWithdraw = new uint256[](1);
        sharesToWithdraw[0] = _amount;

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

        vm.stopBroadcast();

        vm.startBroadcast(deployerKey);
        receiverContract.mockCCIPReceive(any2EvmMessageQueueWithdrawal);
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

}
