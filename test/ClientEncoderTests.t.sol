// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {
    EigenlayerMsgDecoders,
    DelegationDecoders,
    AgentOwnerSignature
} from "../src/utils/EigenlayerMsgDecoders.sol";

import {ClientEncoders} from "../script/ClientEncoders.sol";
import {ClientSigners} from "../script/ClientSigners.sol";
import {EthSepolia} from "../script/Addresses.sol";



contract ClientEncoderTests is BaseTestEnvironment {

    EigenlayerMsgDecoders public eigenlayerMsgDecoders;
    ClientSigners public clientSignersTest;

    uint256 amount;
    address staker;
    uint256 expiry;
    uint256 execNonce;

    function setUp() public {

        setUpForkedEnvironment();

        amount = 0.0077 ether;
        staker = deployer;
        expiry = 86421;
        execNonce = 0;

        vm.selectFork(ethForkId);
        vm.prank(deployer);
        eigenAgent = agentFactory.spawnEigenAgentOnlyOwner(deployer);

        eigenlayerMsgDecoders = new EigenlayerMsgDecoders();
        // test clientEncoders, create a new instance.
        clientSignersTest = new ClientSigners();
    }

    /*
     *
     *            Functions
     *
     */

    function test_checkSignature_EIP1271() public view {

        bytes32 digestHash = keccak256(abi.encode(bob, alice, deployer));
        address signer = deployer;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerKey, digestHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        clientSignersTest.checkSignature_EIP1271(signer, digestHash, signature);

        vm.assertEq(
            IERC1271.isValidSignature.selector,
            eigenAgent.isValidSignature(digestHash, signature)
        );
    }

    function test_createEigenlayerDepositDigest() public view {

        bytes32 domainSeparator = clientSignersTest.getDomainSeparator(address(strategyManager), EthSepolia.ChainId);

        bytes32 digest1 = clientSignersTest.createEigenlayerDepositDigest(
            strategy,
            tokenL1,
            amount,
            staker,
            execNonce,
            expiry,
            domainSeparator
        );

        bytes32 DEPOSIT_TYPEHASH = keccak256("Deposit(address staker,address strategy,address token,uint256 amount,uint256 nonce,uint256 expiry)");
        bytes32 structHash = keccak256(abi.encode(
            DEPOSIT_TYPEHASH,
            staker,
            strategy,
            tokenL1,
            amount,
            execNonce,
            expiry
        ));
        bytes32 digest2 = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        vm.assertEq(digest1, digest2);
    }

    function test_getDomainSeparator() public view {

        address contractAddr = address(strategyManager);
        uint256 chainid = EthSepolia.ChainId;
        bytes32 DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

        bytes32 domainSeparator1 = keccak256(abi.encode(
            DOMAIN_TYPEHASH,
            keccak256(bytes("EigenLayer")),
            chainid,
            contractAddr
        ));

        bytes32 domainSeparator2 = clientSignersTest.getDomainSeparator(contractAddr, chainid);

        vm.assertEq(domainSeparator1, domainSeparator2);
    }

    // function calculateDelegationApprovalDigestHash(
    //     address staker,
    //     address operator,
    //     address _delegationApprover,
    //     bytes32 approverSalt,
    //     uint256 expiry,
    //     address delegationManagerAddr,
    //     uint256 destinationChainid
    // ) public pure returns (bytes32) {

    //     /// @notice The EIP-712 typehash for the `DelegationApproval` struct used by the contract
    //     bytes32 DELEGATION_APPROVAL_TYPEHASH = keccak256(
    //         "DelegationApproval(address delegationApprover,address staker,address operator,bytes32 salt,uint256 expiry)"
    //     );

    //     // calculate the struct hash
    //     bytes32 approverStructHash = keccak256(
    //         abi.encode(DELEGATION_APPROVAL_TYPEHASH, _delegationApprover, staker, operator, approverSalt, expiry)
    //     );
    //     // calculate the digest hash
    //     bytes32 approverDigestHash = keccak256(abi.encodePacked(
    //         "\x19\x01",
    //         getDomainSeparator(delegationManagerAddr, destinationChainid),
    //         approverStructHash
    //     ));
    //     return approverDigestHash;
    // }

    // function createEigenAgentCallDigestHash(
    //     address _target,
    //     uint256 _value,
    //     bytes memory _data,
    //     uint256 _nonce,
    //     uint256 _chainid,
    //     uint256 _expiry
    // ) public pure returns (bytes32) {

    //     bytes32 structHash = keccak256(abi.encode(
    //         EIGEN_AGENT_EXEC_TYPEHASH,
    //         _target,
    //         _value,
    //         _data,
    //         _nonce,
    //         _chainid,
    //         _expiry
    //     ));
    //     // calculate the digest hash
    //     bytes32 digestHash = keccak256(abi.encodePacked(
    //         "\x19\x01",
    //         getDomainSeparator(_target, _chainid),
    //         structHash
    //     ));

    //     return digestHash;
    // }

    // function signMessageForEigenAgentExecution(
    //     uint256 signerKey,
    //     uint256 chainid,
    //     address targetContractAddr,
    //     bytes memory messageToEigenlayer,
    //     uint256 execNonceEigenAgent,
    //     uint256 expiry
    // ) public view returns (bytes memory) {

    //     bytes memory messageWithSignature;
    //     bytes memory signatureEigenAgent;
    //     {
    //         bytes32 digestHash = createEigenAgentCallDigestHash(
    //             targetContractAddr,
    //             0 ether, // not sending ether
    //             messageToEigenlayer,
    //             execNonceEigenAgent,
    //             chainid, // destination chainid where EigenAgent lives, usually ETH
    //             expiry
    //         );

    //         (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digestHash);
    //         signatureEigenAgent = abi.encodePacked(r, s, v);
    //         address signer = vm.addr(signerKey);

    //         // Join the payload + signer + expiry + signature
    //         // NOTE: the order:
    //         // 1: message
    //         // 2: signer
    //         // 3: expiry
    //         // 4: signature
    //         messageWithSignature = abi.encodePacked(
    //             messageToEigenlayer,
    //             bytes32(abi.encode(signer)), // pad signer to 32byte word
    //             expiry,
    //             signatureEigenAgent
    //         );

    //         checkSignature_EIP1271(signer, digestHash, signatureEigenAgent);
    //     }

    //     return messageWithSignature;
    // }

}
