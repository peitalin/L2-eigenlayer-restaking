// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {MockMultisigSigner} from "./mocks/MockMultisigSigner.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC6551Executable} from "@6551/interfaces/IERC6551Executable.sol";
import {IERC6551Account} from "../src/6551/ERC6551Account.sol";


contract EigenAgentUnitTests is BaseTestEnvironment {

    error CallerNotWhitelisted();
    error SignatureNotFromNftOwner();
    error AlreadySigned();

    uint256 expiry;
    uint256 amount;

    function setUp() public {

        setUpForkedEnvironment();

        expiry = block.timestamp + 1 hours;
        amount = 0.0013 ether;

        vm.selectFork(ethForkId);
        vm.prank(deployer);
        eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_EigenAgent_ExecTypehash() public {
        vm.assertEq(
            keccak256("ExecuteWithSignature(address target,uint256 value,bytes data,uint256 execNonce,uint256 chainId,uint256 expiry)"),
            eigenAgent.EIGEN_AGENT_EXEC_TYPEHASH()
        );
    }

    function test_EigenAgent_DomainTypehash() public {
        vm.assertEq(
            delegationManager.DOMAIN_TYPEHASH(),
            eigenAgent.DOMAIN_TYPEHASH()
        );
    }

    function test_GetAgentOwner() public view {
        vm.assertEq(
            address(deployer),
            address(eigenAgent.getAgentOwner())
        );
    }

    function test_EigenAgent_ExecuteWithSignatures() public {

        vm.startBroadcast(deployerKey);
        IEigenAgent6551 eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(bob);
        vm.stopBroadcast();

        vm.startBroadcast(bobKey);

        uint256 execNonce0 = eigenAgent.execNonce();
        // encode a simple getSenderContractL2Addr call
        bytes memory data = abi.encodeWithSelector(receiverContract.getSenderContractL2Addr.selector);

        bytes32 digestHash = createEigenAgentCallDigestHash(
            address(receiverContract),
            0 ether,
            data,
            execNonce0,
            block.chainid,
            expiry
        );
        bytes memory signature;
        {
            // generate ECDSA signature
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, digestHash);
            signature = abi.encodePacked(r, s, v);
        }
        checkSignature_EIP1271(bob, digestHash, signature);
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
            expiry,
            signature
        );

        // msg.sender = ReceiverContract's address
        address senderTargetAddr = receiverContract.getSenderContractL2Addr();
        address sender1 = abi.decode(result, (address));

        require(sender1 == senderTargetAddr, "call did not return the same address");
        vm.stopBroadcast();

        // should fail if anyone else tries to call with Bob's EigenAgent without Bob's signature
        vm.startBroadcast(address(receiverContract));
        vm.expectRevert("Invalid signer");
        EigenAgent6551(payable(address(eigenAgent))).execute(
            address(receiverContract),
            0 ether,
            abi.encodeWithSelector(receiverContract.getSenderContractL2Addr.selector),
            0
        );

        vm.stopBroadcast();
    }

    function test_EigenAgent_RevertOnInvalidSignature() public {

        uint256 execNonce0 = eigenAgent.execNonce();
        // alice signs
        (
            bytes memory data1,
            bytes32 digestHash1,
            bytes memory signature1
        ) = createEigenAgentDepositSignature(
            aliceKey,
            amount,
            execNonce0
        );

        vm.assertEq(
            eigenAgent.isValidSignature(digestHash1, signature1),
            bytes4(0) // returns bytes4(0) when signature verification fails
        );

        // alice attempts to execute using deployer's EigenAgent
        vm.expectRevert(abi.encodeWithSelector(SignatureNotFromNftOwner.selector));
        eigenAgent.executeWithSignature(
            address(strategyManager), // strategyManager
            0,
            data1, // encodeDepositIntoStrategyMsg
            expiry,
            signature1
        );
    }

    function test_EigenAgent_Multisig_Execute() public {

        vm.startBroadcast(deployer);
        MockMultisigSigner multisig = new MockMultisigSigner();

        multisig.addAdmin(bob);
        multisig.addAdmin(alice);

        IEigenAgent6551 eigenAgent2 = agentFactory.spawnEigenAgentOnlyOwner(address(payable(multisig)));
        vm.stopBroadcast();

        vm.assertEq(eigenAgent2.getAgentOwner(), address(multisig));

        uint256 aliceBalanceBefore = alice.balance;

        vm.deal(address(eigenAgent2), 1 ether);
        vm.deal(address(multisig), 1 ether);

        //////////////////////////////////
        // eigenagent can execute as NFT owner() == multisig
        vm.prank(address(multisig));
        IERC6551Executable(address(eigenAgent2)).execute(
            payable(alice),
            0.5 ether,
            "",
            0
        );

        vm.assertEq(address(eigenAgent2).balance, 0.5 ether);
        vm.assertEq(alice.balance, aliceBalanceBefore + 0.5 ether);
        vm.assertEq(eigenAgent2.execNonce(), 1);
    }

    function test_EigenAgent_Multisig_Execute_EIP1271Signatures() public {

        vm.startBroadcast(deployer);
        MockMultisigSigner multisig = new MockMultisigSigner();

        multisig.addAdmin(bob);
        multisig.addAdmin(alice);

        IEigenAgent6551 eigenAgent2 = agentFactory.spawnEigenAgentOnlyOwner(address(payable(multisig)));
        vm.stopBroadcast();

        vm.assertEq(eigenAgent2.getAgentOwner(), address(multisig));

        uint256 aliceBalanceBefore = alice.balance;

        vm.deal(address(eigenAgent2), 1 ether);
        vm.deal(address(multisig), 1 ether);

        //////////////////////////////////
        uint256 execNonce = 0;
        address targetContract = address(agentFactory);

        bytes memory spawnMessage = abi.encodeWithSignature("spawnEigenAgentOnlyOwner(address)", alice);

        bytes32 digestHash = createEigenAgentCallDigestHash(
            targetContract,
            0 ether, // not sending ether
            spawnMessage,
            execNonce,
            block.chainid, // destination chainid where EigenAgent lives, usually ETH
            expiry
        );

        bytes memory messageWithSignatureBob;
        bytes memory sigBob;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, digestHash);
            sigBob = abi.encodePacked(r, s, v);
            address signer = vm.addr(bobKey);

            messageWithSignatureBob = abi.encodePacked(
                spawnMessage,
                bytes32(abi.encode(signer)), // pad signer to 32byte word
                expiry,
                sigBob
            );
        }

        bytes memory messageWithSignatureAlice;
        bytes memory sigAlice;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digestHash);
            sigAlice = abi.encodePacked(r, s, v);
            address signer = vm.addr(aliceKey);

            messageWithSignatureAlice = abi.encodePacked(
                spawnMessage,
                bytes32(abi.encode(signer)), // pad signer to 32byte word
                expiry,
                sigAlice
            );
        }

        // 1st admin signs
        multisig.signHash(digestHash, sigAlice);
        // isValidSignature fails, as only 1 admin signed (out of 2)
        vm.assertNotEq(
            multisig.isValidSignature(digestHash, sigAlice),
            IERC1271.isValidSignature.selector
        );

        // 1st admin tries to double sign and fails
        vm.expectRevert(abi.encodeWithSelector(AlreadySigned.selector));
        multisig.signHash(digestHash, sigAlice);

        // trying to execute call without having 2 signers on the multsig fails
        vm.prank(address(multisig));
        vm.expectRevert(abi.encodeWithSelector(SignatureNotFromNftOwner.selector));
        eigenAgent2.executeWithSignature(
            targetContract,
            0 ether,
            spawnMessage,
            expiry,
            sigAlice
        );

        // 2nd admin signs
        multisig.signHash(digestHash, sigBob);
        // Now this digestHash is valid
        vm.assertEq(
            multisig.isValidSignature(digestHash, sigAlice),
            IERC1271.isValidSignature.selector
        );

        // add eigenAgent2 as AgentFactory admin for permissions to spawn EigenAgent
        vm.prank(deployer);
        agentFactory.addAdmin(address(eigenAgent2));

        // dispatch message from multisig, using any of the admin signatures
        vm.prank(address(multisig));
        eigenAgent2.executeWithSignature(
            targetContract,
            0 ether,
            spawnMessage,
            expiry,
            sigBob
            // sigAlice
        );
        // using any signature from any Admin suffices

        require(
            agentFactory.getEigenAgentOwnerTokenId(alice) > 1,
            "minted for Alice via multisig (owner of EigenAgent)"
        );
    }

    function test_EigenAgent_ApproveByWhitelistedContract() public {

        address someSpenderContract = address(agentFactory);

        vm.expectRevert(abi.encodeWithSelector(CallerNotWhitelisted.selector));
        eigenAgent.approveByWhitelistedContract(
            someSpenderContract,
            address(tokenL1),
            amount
        );

        vm.prank(bob);
        vm.expectRevert("Not admin or owner");
        eigenAgentOwner721.addToWhitelistedCallers(bob);

        vm.startBroadcast(deployer);
        {
            eigenAgentOwner721.addToWhitelistedCallers(deployer);

            eigenAgent.approveByWhitelistedContract(
                someSpenderContract,
                address(tokenL1),
                amount
            );
            eigenAgentOwner721.removeFromWhitelistedCallers(deployer);
            vm.expectRevert(abi.encodeWithSelector(CallerNotWhitelisted.selector));
            eigenAgent.approveByWhitelistedContract(
                someSpenderContract,
                address(tokenL1),
                amount
            );
        }
        vm.stopBroadcast();
    }


    function test_EigenAgent_DepositTransferThenWithdraw() public {

        //////////////////////////////////////////////////////
        /// Receiver -> EigenAgent -> Eigenlayer calls
        //////////////////////////////////////////////////////

        vm.startBroadcast(deployerKey);
        IEigenAgent6551 eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(bob);
        vm.stopBroadcast();

        //////////////////////////////////////////////////////
        //// 1) EigenAgent approves StrategyManager to transfer tokens
        //////////////////////////////////////////////////////
        uint256 execNonce0 = eigenAgent.execNonce();
        {
            vm.startBroadcast(address(receiverContract));
            (
                bytes memory data0,
                bytes32 digestHash0,
                bytes memory signature0
            ) = createEigenAgentERC20ApproveSignature(
                bobKey,
                address(tokenL1),
                address(strategyManager),
                amount,
                execNonce0
            );
            checkSignature_EIP1271(bob, digestHash0, signature0);

            eigenAgent.executeWithSignature(
                address(tokenL1), // CCIP-BnM token
                0 ether, // value
                data0,
                expiry,
                signature0
            );

            // receiver sends eigenAgent tokens
            tokenL1.transfer(address(eigenAgent), amount);
            vm.stopBroadcast();
        }

        //////////////////////////////////////////////////////
        //// 2) EigenAgent Deposits into StrategyManager
        //////////////////////////////////////////////////////
        uint256 execNonce1 = eigenAgent.execNonce();
        {
            vm.startBroadcast(address(receiverContract));
            (
                bytes memory data1,
                bytes32 digestHash1,
                bytes memory signature1
            ) = createEigenAgentDepositSignature(
                bobKey,
                amount,
                execNonce1
            );
            checkSignature_EIP1271(bob, digestHash1, signature1);

            eigenAgent.executeWithSignature(
                address(strategyManager), // strategyManager
                0,
                data1, // encodeDepositIntoStrategyMsg
                expiry,
                signature1
            );
            vm.stopBroadcast();
        }

        //////////////////////////////////////////////////////
        //// 3) Transfer EigenAgentOwner NFT to Alice
        //////////////////////////////////////////////////////
        {
            vm.startBroadcast(bob);

            uint256 transferredTokenId = agentFactory.getEigenAgentOwnerTokenId(bob);
            IEigenAgentOwner721 eigenAgentOwner721 = agentFactory.eigenAgentOwner721();
            eigenAgentOwner721.approve(alice, transferredTokenId);

            vm.expectEmit(true, true, true, true);
            emit IAgentFactory.EigenAgentOwnerUpdated(bob, alice, transferredTokenId);
            eigenAgentOwner721.safeTransferFrom(bob, alice, transferredTokenId);

            require(
                eigenAgentOwner721.ownerOf(transferredTokenId) == alice,
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
            sharesToWithdraw[0] = amount;

            IDelegationManager.QueuedWithdrawalParams memory queuedWithdrawal =
                IDelegationManager.QueuedWithdrawalParams({
                    strategies: strategiesToWithdraw,
                    shares: sharesToWithdraw,
                    withdrawer: address(eigenAgent)
                });

            queuedWithdrawalParams = new IDelegationManager.QueuedWithdrawalParams[](1);
            queuedWithdrawalParams[0] = queuedWithdrawal;

            uint256 execNonce2 = eigenAgent.execNonce();
            (
                bytes memory data2,
                bytes32 digestHash2,
                bytes memory signature2
            ) = createEigenAgentQueueWithdrawalsSignature(
                aliceKey,
                execNonce2,
                queuedWithdrawalParams
            );
            checkSignature_EIP1271(alice, digestHash2, signature2);

            bytes memory result = eigenAgent.executeWithSignature(
                address(delegationManager), // delegationManager
                0,
                data2, // encodeQueueWithdrawals
                expiry,
                signature2
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
        uint256 execNonce,
        IDelegationManager.QueuedWithdrawalParams[] memory queuedWithdrawalParams
    ) public view returns (bytes memory, bytes32, bytes memory) {

        bytes memory data = EigenlayerMsgEncoders.encodeQueueWithdrawalsMsg(
            queuedWithdrawalParams
        );

        bytes32 digestHash = createEigenAgentCallDigestHash(
            address(delegationManager), // target to call
            0 ether,
            data,
            execNonce,
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


    function createEigenAgentERC20ApproveSignature(
        uint256 signerKey,
        address targetToken,
        address to,
        uint256 _amount,
        uint256 execNonce
    ) public view returns (bytes memory, bytes32, bytes memory) {

        bytes memory data = abi.encodeWithSelector(
            // bytes4(keccak256("approve(address,uint256)")),
            IERC20.approve.selector,
            to,
            _amount
        );

        bytes32 digestHash = createEigenAgentCallDigestHash(
            targetToken, // CCIP-BnM token
            0 ether,
            data,
            execNonce,
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
        uint256 _amount,
        uint256 _nonce
    ) public view returns (bytes memory, bytes32, bytes memory) {

        bytes memory data = EigenlayerMsgEncoders.encodeDepositIntoStrategyMsg(
            address(strategy),
            address(tokenL1),
            _amount
        );

        bytes32 digestHash = createEigenAgentCallDigestHash(
            address(strategyManager),
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

    function test_EigenAgent_ValidSigners() public {

        // bob is not valid signer
        vm.assertTrue(
            eigenAgent.isValidSigner(bob, "") != IERC6551Account.isValidSigner.selector
        );
        // deployer is the owner of the eigenAgent, valid signer
        vm.assertEq(
            eigenAgent.isValidSigner(deployer, ""),
            IERC6551Account.isValidSigner.selector
        );

        vm.deal(address(eigenAgent), 1 ether);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(deployer);
        IERC6551Executable(address(eigenAgent)).execute(
            payable(alice),
            0.5 ether,
            "",
            0
        );

        vm.assertEq(address(eigenAgent).balance, 0.5 ether);
        vm.assertEq(alice.balance, aliceBalanceBefore + 0.5 ether);
        vm.assertEq(eigenAgent.execNonce(), 1);
    }

    function test_EigenAgent_SupportsInterface() public view {

        IERC6551Account accountInstance = IERC6551Account(payable(eigenAgent));

        accountInstance.supportsInterface(
            type(IERC165).interfaceId
        );
        accountInstance.supportsInterface(
            type(IERC6551Account).interfaceId
        );
        accountInstance.supportsInterface(
            type(IERC6551Executable).interfaceId
        );
    }

}
