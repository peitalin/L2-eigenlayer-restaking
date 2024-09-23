// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC6551Account} from "@6551/examples/simple/ERC6551Account.sol";

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";


contract UnitTests_Compare6551Costs is BaseTestEnvironment {

    ProxyAdmin proxyAdmin;

    function setUp() public {

        setUpLocalEnvironment();
        proxyAdmin = new ProxyAdmin();
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_Compare6551DeploymentCosts() public {

        EigenAgent6551 defaultAgent = new EigenAgent6551();
        ERC6551Account defaultAgent2 = new ERC6551Account();

        IEigenAgent6551 testAgentGasCost = IEigenAgent6551(payable(Clones.clone(address(defaultAgent))));

        vm.prank(deployer);
        IEigenAgent6551 agent1 = agentFactory.spawnEigenAgentOnlyOwner(alice);
        vm.prank(deployer);
        IEigenAgent6551 agent2 = agentFactory.spawnEigenAgentOnlyOwner(bob);

        vm.assertEq(agent1.EIGEN_AGENT_EXEC_TYPEHASH(), agent2.EIGEN_AGENT_EXEC_TYPEHASH());
        vm.assertEq(defaultAgent.EIGEN_AGENT_EXEC_TYPEHASH(), agent1.EIGEN_AGENT_EXEC_TYPEHASH());
        vm.assertEq(defaultAgent.EIGEN_AGENT_EXEC_TYPEHASH(), agent2.EIGEN_AGENT_EXEC_TYPEHASH());

        bytes memory testMessage = abi.encodeWithSelector(IERC721.balanceOf.selector, address(alice));
        address targetContract = address(eigenAgentOwner721);
        uint256 expiry = block.timestamp;

        // simulate agents executing messages
        bytes memory sig1 = signMessage(
            aliceKey,
            targetContract,
            testMessage,
            0, // execNonce = 0
            expiry
        );
        agent1.executeWithSignature(targetContract, 0, testMessage, expiry, sig1);

        bytes memory sig2 = signMessage(
            aliceKey,
            targetContract,
            testMessage,
            1, // execNonce = 1
            expiry
        );
        agent1.executeWithSignature(targetContract, 0, testMessage, expiry, sig2);

        bytes memory sig3 = signMessage(
            bobKey,
            targetContract,
            testMessage,
            0, // execNonce = 0
            expiry
        );
        agent2.executeWithSignature(targetContract, 0, testMessage, expiry, sig3);

        vm.assertEq(agent1.execNonce(), 2);
        vm.assertEq(agent2.execNonce(), 1);
        vm.assertEq(defaultAgent.execNonce(), 0);
    }

    function signMessage(
        uint256 signerKey,
        address targetContractAddr,
        bytes memory message,
        uint256 execNonce,
        uint256 expiry
    ) public view returns (bytes memory) {

        bytes32 digestHash = createEigenAgentCallDigestHash(
            targetContractAddr,
            0 ether, // not sending ether
            message,
            execNonce,
            block.chainid, // destination chainid where EigenAgent lives: L1 Ethereum
            expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digestHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        address signer = vm.addr(signerKey);

        bytes memory messageWithSignature = abi.encodePacked(
            message,
            bytes32(abi.encode(signer)), // pad signer to 32byte word
            expiry,
            signature
        );

        return signature;
    }

}

