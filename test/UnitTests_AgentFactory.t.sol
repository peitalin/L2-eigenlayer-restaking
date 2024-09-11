// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";
import {AgentFactory} from "../src/6551/AgentFactory.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {ERC6551Registry} from "@6551/ERC6551Registry.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";



contract UnitTests_AgentFactory is BaseTestEnvironment {

    error CallerNotWhitelisted();
    error SignatureNotFromNftOwner();
    error AddressZero(string msg);

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

    function test_AgentFactory_SetContracts() public {

        vm.expectRevert(abi.encodeWithSelector(
            AddressZero.selector,
            "AgentFactory.setRestakingConnector: cannot be address(0)"
        ));
        vm.prank(deployer);
        agentFactory.setRestakingConnector(address(0));

        vm.expectRevert(abi.encodeWithSelector(
            AddressZero.selector,
            "AgentFactory.set6551Registry: cannot be address(0)"
        ));
        vm.prank(deployer);
        agentFactory.set6551Registry(IERC6551Registry(address(0)));

        vm.expectRevert(abi.encodeWithSelector(
            AddressZero.selector,
            "AgentFactory.setEigenAgentOwner721: cannot be address(0)"
        ));
        vm.prank(deployer);
        agentFactory.setEigenAgentOwner721(IEigenAgentOwner721(address(0)));

        vm.prank(deployer);
        agentFactory.setEigenAgentOwner721(IEigenAgentOwner721(address(eigenAgentOwner721)));
    }

    function test_AgentFactory_Initialize() public {

        ProxyAdmin pa = new ProxyAdmin();
        AgentFactory agentFactoryImpl = new AgentFactory();

        vm.expectRevert(abi.encodeWithSelector(
            AddressZero.selector,
            "ERC6551Registry cannot be address(0)"
        ));
        IAgentFactory(payable(address(
            new TransparentUpgradeableProxy(
                address(agentFactoryImpl),
                address(pa),
                abi.encodeWithSelector(
                    AgentFactory.initialize.selector,
                    address(0), // 6551 registry
                    eigenAgentOwner721
                )
            )
        )));

        vm.expectRevert(abi.encodeWithSelector(
            AddressZero.selector,
            "EigenAgentOwner721 cannot be address(0)"
        ));
        IAgentFactory(payable(address(
            new TransparentUpgradeableProxy(
                address(agentFactoryImpl),
                address(pa),
                abi.encodeWithSelector(
                    AgentFactory.initialize.selector,
                    vm.addr(123123), // 6551 registry
                    address(0)
                )
            )
        )));
    }

    function test_EigenAgentOwner721_SetAgentFactory() public {

        vm.prank(deployer);
        vm.expectRevert("AgentFactory cannot be address(0)");
        eigenAgentOwner721.setAgentFactory(IAgentFactory(address(0)));
    }

    function test_EigenAgentOwner721_Mint_AgentFactoryOnly() public {

        vm.prank(deployer);
        vm.expectRevert("Caller not AgentFactory");
        eigenAgentOwner721.mint(bob);

        vm.prank(bob);
        vm.expectRevert("Caller not AgentFactory");
        eigenAgentOwner721.mint(bob);

        vm.prank(address(agentFactory));
        eigenAgentOwner721.mint(bob);

        vm.assertEq(eigenAgentOwner721.balanceOf(bob), 1);
    }

    function test_updateEigenAgentOwnerTokenId_OnlyCallable_EigenAgentOwner721() public {

        uint256 tokenId = agentFactory.getEigenAgentOwnerTokenId(deployer);

        vm.prank(bob);
        vm.expectRevert("AgentFactory.updateEigenAgentOwnerTokenId: caller not EigenAgentOwner721 contract");
        agentFactory.updateEigenAgentOwnerTokenId(deployer, bob, tokenId);

        // transer to bob
        vm.prank(address(eigenAgentOwner721));
        agentFactory.updateEigenAgentOwnerTokenId(deployer, bob, tokenId);

        uint256 tokenId2 = agentFactory.getEigenAgentOwnerTokenId(bob);
        vm.assertEq(tokenId, tokenId2);

        // transer back to deployer
        vm.prank(address(eigenAgentOwner721));
        agentFactory.updateEigenAgentOwnerTokenId(bob, deployer, tokenId);

        uint256 tokenId3 = agentFactory.getEigenAgentOwnerTokenId(deployer);

        vm.assertEq(tokenId2, tokenId3);
    }
}
