// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IDelegationManager} from "@eigenlayer-contracts/interfaces/IDelegationManager.sol";
import {IStrategy} from "@eigenlayer-contracts/interfaces/IStrategy.sol";
import {
    IERC6551Executable,
    IERC6551Account as IERC6551
} from "@6551/examples/simple/ERC6551Account.sol";

import {EigenlayerMsgEncoders} from "../src/utils/EigenlayerMsgEncoders.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {MockMultisigSigner} from "./mocks/MockMultisigSigner.sol";


contract UnitTests_EigenAgent is BaseTestEnvironment {

    error CallerNotWhitelisted(string reason);
    error SignatureInvalid(string reason);
    error AlreadySigned();

    uint256 expiry;
    uint256 amount;

    function setUp() public {

        setUpLocalEnvironment();

        expiry = block.timestamp + 1 hours;
        amount = 0.0013 ether;

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
            delegationManager.domainSeparator(),
            eigenAgent.domainSeparator(address(delegationManager), block.chainid)
        );
        vm.assertEq(
            delegationManager.DOMAIN_TYPEHASH(),
            eigenAgent.DOMAIN_TYPEHASH()
        );
    }

    function test_EigenAgent_Client_DigestHashsEqual() public view {

        bytes memory message1 = encodeMintEigenAgentMsg(deployer);

        bytes32 digestHashClient = createEigenAgentCallDigestHash(
            address(delegationManager),
            0 ether,
            message1,
            1,
            block.chainid,
            expiry
        );
        bytes32 digestHashEigenAgent = eigenAgent.createEigenAgentCallDigestHash(
            address(delegationManager),
            0 ether,
            message1,
            1,
            block.chainid,
            expiry
        );

        vm.assertEq(digestHashClient, digestHashEigenAgent);
    }

    function test_EigenAgent_GetOwner() public view {
        vm.assertEq(
            address(deployer),
            address(eigenAgent.owner())
        );
    }

    function test_EigenAgent_CanOnlySpawnOneEigenAgent() public {
        vm.startBroadcast(deployerKey);
        agentFactory.spawnEigenAgentOnlyOwner(bob);

        vm.expectRevert("User already has an EigenAgent");
        agentFactory.spawnEigenAgentOnlyOwner(bob);
        vm.stopBroadcast();
    }

    function test_EigenAgent_ExecuteWithSignatures() public {

        vm.startBroadcast(deployerKey);
        IEigenAgent6551 eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(bob);
        vm.stopBroadcast();

        vm.startBroadcast(bobKey);

        uint256 execNonce0 = eigenAgent.execNonce();
        // encode a simple getSenderContractL2Addr call
        bytes memory data = abi.encodeWithSelector(receiverContract.getSenderContractL2Addr.selector);

        bytes32 digestHash = eigenAgent.createEigenAgentCallDigestHash(
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
        vm.expectRevert(abi.encodeWithSelector(
            SignatureInvalid.selector,
            "Invalid signer, or incorrect digestHash parameters."
        ));
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

        vm.assertEq(eigenAgent2.owner(), address(multisig));

        uint256 aliceBalanceBefore = alice.balance;

        vm.deal(address(eigenAgent2), 1 ether);
        vm.deal(address(multisig), 1 ether);

        // EigenAgent can execute as NFT owner() == multisig
        vm.prank(address(multisig));
        eigenAgent2.execute(
            payable(alice),
            0.5 ether,
            "",
            0
        );

        vm.assertEq(address(eigenAgent2).balance, 0.5 ether);
        vm.assertEq(alice.balance, aliceBalanceBefore + 0.5 ether);
        // execute() only increments state variable, not execNonce (only for executeWithSignature)
        // this prevents L1 executions from invalidating async L2 executeWithSignature calls
        vm.assertEq(eigenAgent2.execNonce(), 0);
        vm.assertEq(eigenAgent2.state(), 1);

        // operation must == 0 (call operations only)
        vm.prank(address(multisig));
        vm.expectRevert("Only call operations are supported");
        eigenAgent2.execute(
            payable(alice),
            0.1 ether,
            "",
            1 // operation code
        );
    }

    function test_EigenAgent_Multisig_EIP1271Signatures_Execute() public {

        vm.startBroadcast(deployer);
        MockMultisigSigner multisig = new MockMultisigSigner();

        multisig.addAdmin(bob);
        multisig.addAdmin(alice);

        IEigenAgent6551 eigenAgent2 = agentFactory.spawnEigenAgentOnlyOwner(address(payable(multisig)));
        vm.stopBroadcast();

        vm.assertEq(eigenAgent2.owner(), address(multisig));

        vm.deal(address(eigenAgent2), 1 ether);
        vm.deal(address(multisig), 1 ether);

        //////////////////////////////////
        uint256 execNonce = 0;
        address targetContract = address(agentFactory);

        bytes memory spawnMessage = abi.encodeWithSignature("spawnEigenAgentOnlyOwner(address)", alice);

        bytes32 digestHash = eigenAgent2.createEigenAgentCallDigestHash(
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
        vm.expectRevert(abi.encodeWithSelector(
            SignatureInvalid.selector,
            "Invalid signer, or incorrect digestHash parameters."
        ));
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

        // send message from multisig with any signature, multisig already has 2 admin signatures
        bytes memory anySignature = abi.encode("0x123123");

        vm.prank(address(multisig));
        eigenAgent2.executeWithSignature(
            targetContract,
            0 ether,
            spawnMessage,
            expiry,
            anySignature
        );

        require(
            agentFactory.getEigenAgentOwnerTokenId(alice) > 1,
            "minted for Alice via multisig (owner of EigenAgent)"
        );
    }

    function test_RevertOnCallingWrongFunctions_Execute() public {

        // try call agentFactory with the wrong function selectors
        vm.prank(deployer);
        vm.expectRevert();
        eigenAgent.execute(
            address(agentFactory),
            0 ether,
            encodeMintEigenAgentMsg(alice), // should fail as targetContract does not have this function
            0 // operation code
        );

    }

    function test_RevertOnCallingWrongFunctions_ExecuteWithSignature() public {

        (
            , // bytes memory data1,
            , // bytes32 digestHash1,
            bytes memory signature1
        ) = createEigenAgentDepositSignature(
            deployerKey,
            amount,
            0
        );
        // try call agentfactor with the wrong function selectors
        vm.prank(deployer);
        vm.expectRevert();
        eigenAgent.executeWithSignature(
            address(strategyManager), // strategyManager
            0,
            encodeMintEigenAgentMsg(alice), // should fail as targetContract does not have this function
            expiry,
            signature1
        );
    }

    function test_EigenAgent_ApproveByWhitelistedContract() public {

        address someSpenderContract = address(agentFactory);

        vm.expectRevert(abi.encodeWithSelector(
            CallerNotWhitelisted.selector,
            "EigenAgent: caller not allowed"
        ));
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
            vm.expectRevert(abi.encodeWithSelector(
                CallerNotWhitelisted.selector,
                "EigenAgent: caller not allowed"
            ));
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

    function test_EigenAgent_HoldsOnlyOneAgentAtATime() public {

        // Mint Bob and EigenAgent
        vm.prank(deployer);
        IEigenAgent6551 eigenAgent1 = agentFactory.spawnEigenAgentOnlyOwner(bob);

        // Try Mint Bob another EigenAgent (total: 2) but fail
        vm.prank(deployer);
        vm.expectRevert("User already has an EigenAgent");
        agentFactory.spawnEigenAgentOnlyOwner(bob);

        // Bob transfers EigenAgent to Alice
        (,, uint256 tokenId1) = eigenAgent1.token();
        vm.prank(bob);
        eigenAgentOwner721.transferFrom(bob, alice, tokenId1);

        // Mint Bob another EigenAgent
        vm.prank(deployer);
        IEigenAgent6551 eigenAgent2 = agentFactory.spawnEigenAgentOnlyOwner(bob);
        (,, uint256 tokenId2) = eigenAgent2.token();

        // Reverts when Bob trys giving Alice another EigenAgent (total: 2)
        vm.expectRevert("Cannot own more than one EigenAgentOwner721 at a time.");
        vm.prank(bob);
        eigenAgentOwner721.safeTransferFrom(bob, alice, tokenId2 , "");

        // they should have one EigenAgent each
        vm.assertEq(eigenAgentOwner721.balanceOf(alice), 1);
        vm.assertEq(eigenAgentOwner721.balanceOf(bob), 1);
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
            eigenAgent.isValidSigner(bob, "") != IERC6551.isValidSigner.selector
        );
        // deployer is the owner of the eigenAgent, valid signer
        vm.assertEq(
            eigenAgent.isValidSigner(deployer, ""),
            IERC6551.isValidSigner.selector
        );

        vm.deal(address(eigenAgent), 1 ether);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(deployer);
        eigenAgent.execute(
            payable(alice),
            0.5 ether,
            "",
            0
        );

        vm.assertEq(address(eigenAgent).balance, 0.5 ether);
        vm.assertEq(alice.balance, aliceBalanceBefore + 0.5 ether);
        // execute() only increments state variable, not execNonce (only for executeWithSignature)
        // this prevents L1 executions from invalidating async L2 executeWithSignature calls
        vm.assertEq(eigenAgent.execNonce(), 0);
        vm.assertEq(eigenAgent.state(), 1);
    }

    function test_EigenAgent_SupportsInterface() public view {

        eigenAgent.supportsInterface(
            type(IERC165).interfaceId
        );
        eigenAgent.supportsInterface(
            type(IERC6551).interfaceId
        );
        eigenAgent.supportsInterface(
            type(IERC6551Executable).interfaceId
        );
    }

    function test_EigenAgent_GetAgentOwnerToken() public view {

        (
            uint256 chainId,
            address tokenContract,
            uint256 tokenId
        ) = eigenAgent.token();

        vm.assertEq(chainId, block.chainid);
        vm.assertEq(tokenContract, address(eigenAgentOwner721));
        vm.assertTrue(tokenId >= 1);
    }
}
