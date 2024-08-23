// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IRewardsCoordinator} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import {IPauserRegistry} from "eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {StrategyManager} from "eigenlayer-contracts/src/contracts/core/StrategyManager.sol";

import {IERC20Minter} from "../src/interfaces/IERC20Minter.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";
import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {RestakingConnector} from "../src/RestakingConnector.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {EigenlayerDepositWithSignatureParams} from "../src/interfaces/IEigenlayerMsgDecoders.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";

// 6551 accounts
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC6551Registry} from "@6551/ERC6551Registry.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";



contract CCIP_Eigen_Deposit6551Tests is Test {

    DeployOnEthScript public deployOnEthScript;
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

    uint256 public initialReceiverBalance = 5 ether;

    ERC6551Registry public registry;
    EigenAgentOwner721 public eigenAgentOwnerNft;

    // call params
    address _target;
    uint256 _value;
    uint256 _expiry;
    uint256 _nonce;
    uint256 _amount;
    bytes _data;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        bobKey = uint256(56789);
        bob = vm.addr(bobKey);
        vm.deal(bob, 1 ether);

        deployOnEthScript = new DeployOnEthScript();
        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
        signatureUtils = new SignatureUtilsEIP1271();

        uint256 l2ForkId = vm.createFork("basesepolia");
        uint256 ethForkId = vm.createSelectFork("ethsepolia");

        //// Configure Eigenlayer contracts
        (
            strategy,
            strategyManager,
            , //IStrategyFactory
            , // pauserRegistry
            delegationManager,
            , // rewardsCoordinator
            token
        ) = deployMockEigenlayerContractsScript.deployEigenlayerContracts(false);

        //// Configure CCIP contracts
        (
            receiverContract,
            restakingConnector
        ) = deployOnEthScript.run();

        erc20Drip = IERC20_CCIPBnM(address(token));

        //// Configure CCIP contracts
        vm.startBroadcast(deployerKey);
        restakingConnector.setEigenlayerContracts(delegationManager, strategyManager, strategy);
        erc20Drip.drip(address(receiverContract));
        erc20Drip.drip(address(receiverContract));
        erc20Drip.drip(address(bob));
        receiverContract.allowlistSender(deployer, true);

        //////// 6551 Registry
        proxyAdmin = new ProxyAdmin();
        registry = new ERC6551Registry();
        eigenAgentOwnerNft = deployEigenAgentOwnerNft("EigenAgent", "EA", proxyAdmin);

        _value = 0 ether;
        _expiry = block.timestamp + 1 hours;

        vm.stopBroadcast();
    }


    function deployEigenAgentOwnerNft(
        string memory name,
        string memory symbol,
        ProxyAdmin _proxyAdmin
    ) public returns (EigenAgentOwner721) {
        EigenAgentOwner721 agentProxy = EigenAgentOwner721(
            address(new TransparentUpgradeableProxy(
                address(new EigenAgentOwner721()),
                address(_proxyAdmin),
                abi.encodeWithSelector(
                    EigenAgentOwner721.initialize.selector,
                    name,
                    symbol
                )
            ))
        );
        return agentProxy;
    }


    function spawn6551EigenAgent() public returns (EigenAgent6551) {
        vm.startBroadcast(deployerKey);
        bytes32 salt = bytes32(uint256(200));
        uint256 tokenId = eigenAgentOwnerNft.mint(bob);

        EigenAgent6551 _eigenAgentImpl = new EigenAgent6551();
        EigenAgent6551 eigenAgent = EigenAgent6551(payable(
            registry.createAccount(
                address(_eigenAgentImpl),
                salt,
                block.chainid,
                address(eigenAgentOwnerNft),
                tokenId
            )
        ));
        vm.stopBroadcast();
        return eigenAgent;
    }


    function test_EigenAgent_ExecuteWithSignatures() public {

        EigenAgent6551 eigenAgent = spawn6551EigenAgent();

        vm.startBroadcast(bobKey);

        _nonce = eigenAgent.execNonce();
        _data = abi.encodeWithSelector(receiverContract.getSenderContractL2Addr.selector);

        bytes32 digestHash = signatureUtils.createEigenAgentCallDigest(
            address(receiverContract),
            _value,
            _data,
            _nonce,
            block.chainid,
            _expiry
        );
        bytes memory signature;
        {
            // generate ECDSA signature
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, digestHash);
            signature = abi.encodePacked(r, s, v);
        }
        signatureUtils.checkSignature_EIP1271(bob, digestHash, signature);
        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        /// Receiver Broadcasts TX
        //////////////////////////////////////////////////////
        vm.startBroadcast(address(receiverContract));

        // console.log("------------------------------------------------------");
        // console.log("eigenAgent:", address(eigenAgent));
        bytes memory result = eigenAgent.executeWithSignature(
            address(receiverContract),
            _value,
            _data,
            _expiry,
            signature
        );
        // console.log("------------------------------------------------------");
        // console.log("receiver  :", address(receiverContract));
        address senderTargetAddr = receiverContract.getSenderContractL2Addr();
        address sender1 = abi.decode(result, (address));
        // console.log("eigenAgent.execute:");
        // console.log(sender1);
        require(sender1 == senderTargetAddr, "call did not return the same address");
        vm.stopBroadcast();

        // should fail if anyone else tries to call with Bob's EigenAgent
        vm.startBroadcast(address(receiverContract));
        vm.expectRevert("Caller is not owner");
        eigenAgent.execute(
            address(receiverContract),
            0 ether,
            abi.encodeWithSelector(receiverContract.getSenderContractL2Addr.selector),
            0
        );
        vm.stopBroadcast();
    }


    function test_CCIP_Eigenlayer_DepositIntoStrategy6551() public {

        _amount = 0.0028 ether;
        _expiry = block.timestamp + 1 days;

        EigenAgent6551 eigenAgent = spawn6551EigenAgent();

        vm.startBroadcast(bobKey);
        _nonce = eigenAgent.execNonce();
        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        /// Receiver -> EigenAgent Broadcasts TX
        //////////////////////////////////////////////////////
        vm.startBroadcast(address(receiverContract));

        erc20Drip.transfer(address(eigenAgent), _amount);

        (
            bytes memory data1,
            bytes32 digestHash1,
            bytes memory signature1
        ) = createEigenAgentERC20ApproveSignature(
            bobKey,
            address(erc20Drip),
            address(strategyManager),
            _amount
        );
        signatureUtils.checkSignature_EIP1271(bob, digestHash1, signature1);

        // eigenAgent approves StrategyManager to transfer tokens
        eigenAgent.executeWithSignature(
            address(erc20Drip), // CCIP-BnM token
            0 ether, // value
            data1,
            _expiry,
            signature1
        );

        // receiver sends eigenAgent tokens
        erc20Drip.transfer(address(eigenAgent), _amount);

        (
            bytes memory data2,
            bytes32 digestHash2,
            bytes memory signature2
        ) = createEigenAgentDepositSignature(
            bobKey,
            _amount,
            0 ether,
            _nonce,
            _expiry
        );
        signatureUtils.checkSignature_EIP1271(bob, digestHash2, signature2);

        bytes memory result = eigenAgent.executeWithSignature(
            address(strategyManager), // strategyManager
            0,
            data2, // encodeDepositIntoStrategyMsg
            _expiry,
            signature2
        );
        uint256 shares1 = abi.decode(result, (uint256));
        console.log("shares1:", shares1);

        vm.stopBroadcast();


        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams;
        {

            IStrategy[] memory strategiesToWithdraw = new IStrategy[](1);
            strategiesToWithdraw[0] = strategy;

            uint256[] memory sharesToWithdraw = new uint256[](1);
            sharesToWithdraw[0] = _amount;

            IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal =
                IDelegationManager.QueuedWithdrawalParams({
                    strategies: strategiesToWithdraw,
                    shares: sharesToWithdraw,
                    withdrawer: address(eigenAgent)
                });

            queuedWithdrawalParams = new IDelegationManager.QueuedWithdrawalParams[](1);
            queuedWithdrawalParams[0] = queuedWithdrawal;
        }

        (
            bytes memory data3,
            bytes32 digestHash3,
            bytes memory signature3
        ) = createEigenAgentQueueWithdrawalsSignature(
            bobKey,
            queuedWithdrawalParams
        );
        signatureUtils.checkSignature_EIP1271(bob, digestHash3, signature3);

        result = eigenAgent.executeWithSignature(
            address(delegationManager), // delegationManager
            0,
            data3, // encodeDepositIntoStrategyMsg
            _expiry,
            signature3
        );
        bytes32[] memory withdrawalRoots = abi.decode(result, (bytes32[]));
        console.log("withdrawalRoots:");
        console.logBytes32(withdrawalRoots[0]);

        require(
            withdrawalRoots[0] != bytes32(0),
            "no withdrawalRoot returned by EigenAgent queueWithdrawals"
        );

        // Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](1);
        // destTokenAmounts[0] = Client.EVMTokenAmount({
        //     token: address(token), // CCIP-BnM token address on Eth Sepolia.
        //     amount: amount
        // });
        // Client.Any2EVMMessage memory any2EvmMessage = Client.Any2EVMMessage({
        //     messageId: bytes32(0xffffffffffffffff9999999999999999eeeeeeeeeeeeeeee8888888888888888),
        //     sourceChainSelector: BaseSepolia.ChainSelector, // Arb Sepolia source chain selector
        //     sender: abi.encode(deployer), // bytes: abi.decode(sender) if coming from an EVM chain.
        //     data: abi.encode(string(
        //         EigenlayerMsgEncoders.encodeDepositIntoStrategyWithSignatureMsg(
        //             address(strategy),
        //             address(token),
        //             amount,
        //             staker,
        //             expiry,
        //             signature
        //         )
        //     )), // CCIP abi.encodes a string message when sending
        //     destTokenAmounts: destTokenAmounts // Tokens and their amounts in their destination chain representation.
        // });
        // /////////////////////////////////////
        // //// Send message from CCIP to Eigenlayer
        // /////////////////////////////////////
        // vm.startBroadcast(EthSepolia.Router); // simulate router calling receiverContract on L1
        // receiverContract.mockCCIPReceive(any2EvmMessage);
        // uint256 receiverBalance = token.balanceOf(address(receiverContract));
        // uint256 valueOfShares = strategy.userUnderlying(address(deployer));
        // require(valueOfShares == amount, "valueofShares incorrect");
        // require(strategyManager.stakerStrategyShares(staker, strategy) == amount, "stakerStrategyShares incorrect");
    }

    function createEigenAgentQueueWithdrawalsSignature(
        uint256 signerKey,
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams
    ) public view returns (bytes memory, bytes32, bytes memory) {

        bytes memory data = EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(
            queuedWithdrawalParams
        );

        bytes32 digestHash = signatureUtils.createEigenAgentCallDigest(
            address(delegationManager), // target to call
            0 ether,
            data,
            _nonce,
            block.chainid,
            _expiry
        );

        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digestHash);
            signature = abi.encodePacked(r, s, v);
        }

        return (data, digestHash, signature);
    }


    function createEigenAgentERC20ApproveSignature(
        uint256 signerKey,
        address _token,
        address _to,
        uint256 _amount
    ) public view returns (bytes memory, bytes32, bytes memory) {

        bytes memory data = EigenlayerMsgEncoders.encodeERC20ApproveMsg(
            _to,
            _amount
        );

        bytes32 digestHash = signatureUtils.createEigenAgentCallDigest(
            _token, // CCIP-BnM token
            0 ether,
            data,
            _nonce,
            block.chainid,
            _expiry
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
        uint256 _amount,
        uint256 _value,
        uint256 _nonce,
        uint256 _expiry
    ) public view returns (bytes memory, bytes32, bytes memory) {

        bytes memory data = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
            address(strategy),
            address(token),
            _amount
        );

        bytes32 digestHash = signatureUtils.createEigenAgentCallDigest(
            address(strategyManager),
            _value,
            data,
            _nonce,
            block.chainid,
            _expiry
        );

        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digestHash);
            signature = abi.encodePacked(r, s, v);
        }

        return (data, digestHash, signature);
    }

}
