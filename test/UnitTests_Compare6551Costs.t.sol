// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ProxyAdmin} from "@openzeppelin-v5-contracts/proxy/transparent/ProxyAdmin.sol";
import {Clones} from "@openzeppelin-v5-contracts/proxy/Clones.sol";
import {IERC721} from "@openzeppelin-v5-contracts/token/ERC721/IERC721.sol";
import {ERC6551Account} from "@6551/examples/simple/ERC6551Account.sol";

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {EthSepolia, BaseSepolia} from "../script/Addresses.sol";

import {console} from "forge-std/console.sol";


contract UnitTests_Compare6551Costs is BaseTestEnvironment {

    ProxyAdmin proxyAdmin;

    function setUp() public {

        setUpLocalEnvironment();
        proxyAdmin = new ProxyAdmin(address(this));
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
        ERC6551Account _defaultAgentBob = new ERC6551Account();
        require(address(_defaultAgentBob) != address(0), "defaultAgentBob should be deployed");

        // test agent clone gas cost
        IEigenAgent6551(payable(Clones.clone(address(defaultAgent))));

        vm.prank(deployer);
        IEigenAgent6551 agentAlice = agentFactory.spawnEigenAgentOnlyOwner(alice);
        vm.prank(deployer);
        IEigenAgent6551 agentBob = agentFactory.spawnEigenAgentOnlyOwner(bob);

        vm.assertEq(agentAlice.EIGEN_AGENT_EXEC_TYPEHASH(), agentBob.EIGEN_AGENT_EXEC_TYPEHASH());
        vm.assertEq(defaultAgent.EIGEN_AGENT_EXEC_TYPEHASH(), agentAlice.EIGEN_AGENT_EXEC_TYPEHASH());
        vm.assertEq(defaultAgent.EIGEN_AGENT_EXEC_TYPEHASH(), agentBob.EIGEN_AGENT_EXEC_TYPEHASH());

        bytes memory testMessage = abi.encodeWithSelector(IERC721.balanceOf.selector, address(alice));
        address targetContract = address(eigenAgentOwner721);
        uint256 expiry = block.timestamp;

        console.log("Signing message for agentAlice: ", address(agentAlice));
        // simulate agents executing messages
        bytes memory sig1 = getSignature(
            aliceKey,
            address(agentAlice),
            targetContract,
            testMessage,
            0, // execNonce = 0
            expiry
        );
        vm.startBroadcast(address(restakingConnector));
        agentAlice.executeWithSignature(targetContract, 0, testMessage, expiry, sig1);
        vm.stopBroadcast();

        bytes memory sig2 = getSignature(
            aliceKey,
            address(agentAlice),
            targetContract,
            testMessage,
            1, // execNonce = 1
            expiry
        );
        vm.startBroadcast(address(restakingConnector));
        agentAlice.executeWithSignature(targetContract, 0, testMessage, expiry, sig2);
        vm.stopBroadcast();

        bytes memory sig3 = getSignature(
            bobKey,
            address(agentBob),
            targetContract,
            testMessage,
            0, // execNonce = 0
            expiry
        );
        vm.startBroadcast(address(restakingConnector));
        agentBob.executeWithSignature(targetContract, 0, testMessage, expiry, sig3);
        vm.stopBroadcast();
        vm.assertEq(agentAlice.execNonce(), 2);
        vm.assertEq(agentBob.execNonce(), 1);
        vm.assertEq(defaultAgent.execNonce(), 0);
    }

    function getSignature(
        uint256 signerKey,
        address eigenAgentAddr,
        address targetContractAddr,
        bytes memory message,
        uint256 execNonce,
        uint256 expiry
    ) public view returns (bytes memory) {

        bytes32 digestHash = createEigenAgentCallDigestHash(
            targetContractAddr,
            eigenAgentAddr,
            0 ether, // not sending ether
            message,
            execNonce,
            block.chainid, // destination chainid where EigenAgent lives: L1 Ethereum
            expiry
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hashDigest191(digestHash));
        bytes memory signature = abi.encodePacked(r, s, v);

        return signature;
    }
}

