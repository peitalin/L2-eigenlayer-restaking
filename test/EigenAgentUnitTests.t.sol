// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20_CCIPBnM} from "../src/interfaces/IERC20_CCIPBnM.sol";

import {IStrategyManager} from "eigenlayer-contracts/src/contracts/interfaces/IStrategyManager.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {IReceiverCCIP} from "../src/interfaces/IReceiverCCIP.sol";
import {IRestakingConnector} from "../src/interfaces/IRestakingConnector.sol";
import {ReceiverCCIP} from "../src/ReceiverCCIP.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {DeployReceiverOnL1Script} from "../script/3_deployReceiverOnL1.s.sol";

import {SignatureUtilsEIP1271} from "../src/utils/SignatureUtilsEIP1271.sol";
import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";

// 6551 accounts
import {ERC6551Registry} from "@6551/ERC6551Registry.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {EigenAgent6551TestUpgrade} from "./mocks/EigenAgent6551TestUpgrade.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";



contract CCIP_EigenAgentTests is Test {

    DeployReceiverOnL1Script public deployOnEthScript;
    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;
    SignatureUtilsEIP1271 public signatureUtils;

    uint256 public deployerKey;
    address public deployer;
    uint256 public bobKey;
    address public bob;
    uint256 public aliceKey;
    address public alice;

    IReceiverCCIP public receiverContract;
    IRestakingConnector public restakingConnector;
    IERC20_CCIPBnM public erc20Drip; // has drip faucet functions
    IERC20 public token;

    IStrategyManager public strategyManager;
    IDelegationManager public delegationManager;
    IStrategy public strategy;
    ProxyAdmin public proxyAdmin;

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

        aliceKey = uint256(12344);
        alice = vm.addr(aliceKey);
        vm.deal(alice, 1 ether);

        deployOnEthScript = new DeployReceiverOnL1Script();
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

        _expiry = block.timestamp + 1 hours;
        _nonce = 0;
        _amount = 0.0013 ether;

        vm.stopBroadcast();
    }

    function test_EigenAgent_ExecuteWithSignatures() public {

        vm.startBroadcast(deployerKey);
        EigenAgent6551 eigenAgent = receiverContract.spawnEigenAgentOnlyOwner(bob);
        vm.stopBroadcast();

        vm.startBroadcast(bobKey);

        _nonce = eigenAgent.execNonce();

        // encode a simple readSenderContractL2Addr call
        bytes memory data = abi.encodeWithSelector(receiverContract.readSenderContractL2Addr.selector);

        bytes32 digestHash = signatureUtils.createEigenAgentCallDigestHash(
            address(receiverContract),
            0 ether,
            data,
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

        // msg.sender = EigenAgent's address
        bytes memory result = eigenAgent.executeWithSignature(
            address(receiverContract),
            0 ether,
            data,
            _expiry,
            signature
        );

        // msg.sender = ReceiverContract's address
        address senderTargetAddr = receiverContract.readSenderContractL2Addr();
        address sender1 = abi.decode(result, (address));

        require(sender1 == senderTargetAddr, "call did not return the same address");
        vm.stopBroadcast();

        // should fail if anyone else tries to call with Bob's EigenAgent without Bob's signature
        vm.startBroadcast(address(receiverContract));
        vm.expectRevert("Caller is not owner");
        eigenAgent.execute(
            address(receiverContract),
            0 ether,
            abi.encodeWithSelector(receiverContract.readSenderContractL2Addr.selector),
            0
        );

        vm.stopBroadcast();
    }


    function test_EigenAgent_TestUpgrade() public {
        // Note: 6551 upgrades must be initiated by the NFT owner
        // Unlike UpgradeableBeacons, admin cannot upgrade the implementation for everyone.
        //
        // 6551 uses ERC1167 minimal proxies to save gas, which are not compatible with this flow:
        // Minimal Proxy -> Upgradeable BeaconProxy -> Logic contract
        // See: https://forum.openzeppelin.com/t/using-eip1167-with-upgradability/3217/3
        //
        // We would have to replace 6551 with something that combines:
        // UpgradeableBeacon +
        // Create2 deterministic account creation + registry
        // remove the NFT requirement

        vm.startBroadcast(deployerKey);

        EigenAgent6551 eigenAgentBob = receiverContract.spawnEigenAgentOnlyOwner(bob);
        EigenAgent6551 eigenAgentDeployer = receiverContract.spawnEigenAgentOnlyOwner(deployer);

        ///// create new implementation and upgrade
        EigenAgent6551TestUpgrade eigenAgentUpgradedImpl = new EigenAgent6551TestUpgrade();

        vm.expectRevert("Caller is not owner");
        eigenAgentBob.upgrade(address(eigenAgentUpgradedImpl));

        eigenAgentDeployer.upgrade(address(eigenAgentUpgradedImpl));

        require(
            eigenAgentBob.agentImplVersion() == 1,
            "EigenAgentBob should fail to upgrade to new implementation"
        );
        // check if both eigenAgents have been upgraded to new implementation, or just one?
        require(
            eigenAgentDeployer.agentImplVersion() == 2,
            "EigenAgentDeployer should have upgraded to new implementation"
        );
        vm.stopBroadcast();
    }


    function test_CCIP_EigenAgent_DepositTransferThenWithdraw() public {

        //////////////////////////////////////////////////////
        /// Receiver -> EigenAgent -> Eigenlayer calls
        //////////////////////////////////////////////////////

        vm.startBroadcast(deployerKey);
        EigenAgent6551 eigenAgent = receiverContract.spawnEigenAgentOnlyOwner(bob);
        vm.stopBroadcast();

        vm.startBroadcast(bobKey);
        _nonce = eigenAgent.execNonce();
        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        //// 1) EigenAgent approves StrategyManager to transfer tokens
        //////////////////////////////////////////////////////
        {
            vm.startBroadcast(address(receiverContract));
            (
                bytes memory data1,
                bytes32 digestHash1,
                bytes memory signature1
            ) = createEigenAgentERC20ApproveSignature(
                bobKey,
                address(erc20Drip),
                address(strategyManager),
                _amount,
                _expiry
            );
            signatureUtils.checkSignature_EIP1271(bob, digestHash1, signature1);

            eigenAgent.executeWithSignature(
                address(erc20Drip), // CCIP-BnM token
                0 ether, // value
                data1,
                _expiry,
                signature1
            );

            // receiver sends eigenAgent tokens
            erc20Drip.transfer(address(eigenAgent), _amount);
            vm.stopBroadcast();
        }

        //////////////////////////////////////////////////////
        //// 2) EigenAgent Deposits into StrategyManager
        //////////////////////////////////////////////////////
        {
            vm.startBroadcast(address(receiverContract));

            (
                bytes memory data2,
                bytes32 digestHash2,
                bytes memory signature2
            ) = createEigenAgentDepositSignature(
                bobKey,
                _amount,
                _nonce,
                _expiry
            );
            signatureUtils.checkSignature_EIP1271(bob, digestHash2, signature2);

            eigenAgent.executeWithSignature(
                address(strategyManager), // strategyManager
                0,
                data2, // encodeDepositIntoStrategyMsg
                _expiry,
                signature2
            );
            vm.stopBroadcast();
        }

        //////////////////////////////////////////////////////
        //// 3) Transfer EigenAgentOwner NFT to Alice
        //////////////////////////////////////////////////////
        {
            vm.startBroadcast(bob);

            uint256 transferredTokenId = receiverContract.getEigenAgentOwnerTokenId(bob);
            EigenAgentOwner721 eigenAgentOwnerNft = receiverContract.getEigenAgentOwner721();
            eigenAgentOwnerNft.approve(alice, transferredTokenId);

            vm.expectEmit(true, true, true, true);
            emit ReceiverCCIP.EigenAgentOwnerUpdated(bob, alice, transferredTokenId);
            eigenAgentOwnerNft.safeTransferFrom(bob, alice, transferredTokenId);

            require(
                eigenAgentOwnerNft.ownerOf(transferredTokenId) == alice,
                "alice should be owner of the token"
            );
            vm.stopBroadcast();
        }

        //////////////////////////////////////////////////////
        //// 4) Alice -> EigenAgent Queues Withdrawal from Eigenlayer
        //////////////////////////////////////////////////////
        {
            vm.startBroadcast(address(receiverContract));

            IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams;

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

            (
                bytes memory data3,
                bytes32 digestHash3,
                bytes memory signature3
            ) = createEigenAgentQueueWithdrawalsSignature(
                aliceKey,
                queuedWithdrawalParams
            );
            signatureUtils.checkSignature_EIP1271(alice, digestHash3, signature3);

            bytes memory result = eigenAgent.executeWithSignature(
                address(delegationManager), // delegationManager
                0,
                data3, // encodeQueueWithdrawals
                _expiry,
                signature3
            );

            bytes32[] memory withdrawalRoots = abi.decode(result, (bytes32[]));
            require(
                withdrawalRoots[0] != bytes32(0),
                "no withdrawalRoot returned by EigenAgent queueWithdrawals"
            );

            vm.stopBroadcast();
        }
    }


    function createEigenAgentQueueWithdrawalsSignature(
        uint256 signerKey,
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams
    ) public view returns (bytes memory, bytes32, bytes memory) {

        bytes memory data = EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(
            queuedWithdrawalParams
        );

        bytes32 digestHash = signatureUtils.createEigenAgentCallDigestHash(
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
        address targetToken,
        address to,
        uint256 amount,
        uint256 expiry
    ) public view returns (bytes memory, bytes32, bytes memory) {

        bytes memory data = abi.encodeWithSelector(
            // bytes4(keccak256("approve(address,uint256)")),
            IERC20.approve.selector,
            to,
            amount
        );

        bytes32 digestHash = signatureUtils.createEigenAgentCallDigestHash(
            targetToken, // CCIP-BnM token
            0 ether,
            data,
            _nonce,
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
