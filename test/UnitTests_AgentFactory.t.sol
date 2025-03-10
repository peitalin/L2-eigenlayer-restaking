// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin-v5-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-v5-contracts/proxy/transparent/ProxyAdmin.sol";

import {EigenAgentOwner721} from "../src/6551/EigenAgentOwner721.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";
import {AgentFactory} from "../src/6551/AgentFactory.sol";
import {IAgentFactory} from "../src/6551/IAgentFactory.sol";
import {ERC6551Registry} from "@6551/ERC6551Registry.sol";
import {IERC6551Registry} from "@6551/interfaces/IERC6551Registry.sol";
import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";

contract UnitTests_AgentFactory is BaseTestEnvironment {

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

        ProxyAdmin pa = new ProxyAdmin(address(this));
        AgentFactory agentFactoryImpl = new AgentFactory();
        address mockBaseEigenAgent = vm.addr(4321);
        address mock6551Registry  = vm.addr(12341234);

        vm.expectRevert(abi.encodeWithSelector(
            AddressZero.selector,
            "_erc6551Registry cannot be address(0)"
        ));
        IAgentFactory(payable(address(
            new TransparentUpgradeableProxy(
                address(agentFactoryImpl),
                address(pa),
                abi.encodeWithSelector(
                    AgentFactory.initialize.selector,
                    address(0), // 6551 registry
                    eigenAgentOwner721,
                    mockBaseEigenAgent
                )
            )
        )));

        vm.expectRevert(abi.encodeWithSelector(
            AddressZero.selector,
            "_eigenAgentOwner721 cannot be address(0)"
        ));
        IAgentFactory(payable(address(
            new TransparentUpgradeableProxy(
                address(agentFactoryImpl),
                address(pa),
                abi.encodeWithSelector(
                    AgentFactory.initialize.selector,
                    mock6551Registry,
                    address(0), // eigenAgentOwner721
                    mockBaseEigenAgent
                )
            )
        )));

        vm.expectRevert(abi.encodeWithSelector(
            AddressZero.selector,
            "_baseEigenAgent cannot be address(0)"
        ));
        IAgentFactory(payable(address(
            new TransparentUpgradeableProxy(
                address(agentFactoryImpl),
                address(pa),
                abi.encodeWithSelector(
                    AgentFactory.initialize.selector,
                    mock6551Registry,
                    eigenAgentOwner721,
                    address(0) // baseEigenAgent
                )
            )
        )));


        IAgentFactory agentFactory2 = IAgentFactory(payable(address(
            new TransparentUpgradeableProxy(
                address(agentFactoryImpl),
                address(pa),
                abi.encodeWithSelector(
                    AgentFactory.initialize.selector,
                    mock6551Registry,
                    eigenAgentOwner721,
                    mockBaseEigenAgent
                )
            )
        )));

        vm.assertEq(agentFactory2.baseEigenAgent(), mockBaseEigenAgent);
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

        // transfer to bob
        vm.prank(address(eigenAgentOwner721));
        agentFactory.updateEigenAgentOwnerTokenId(deployer, bob, tokenId);

        uint256 tokenId2 = agentFactory.getEigenAgentOwnerTokenId(bob);
        vm.assertEq(tokenId, tokenId2);

        // transfer back to deployer
        vm.prank(address(eigenAgentOwner721));
        agentFactory.updateEigenAgentOwnerTokenId(bob, deployer, tokenId);

        uint256 tokenId3 = agentFactory.getEigenAgentOwnerTokenId(deployer);

        vm.assertEq(tokenId2, tokenId3);
    }

    function test_AgentFactory_RequiresMatchingRestakingConnectorValue() public {

        vm.startPrank(deployer);
        // Deploy a new AgentFactory with a fresh base EigenAgent
        EigenAgent6551 newBaseEigenAgent = new EigenAgent6551();
        IERC6551Registry newERC6551Registry = IERC6551Registry(address(new ERC6551Registry()));
        address mockRestakingConnector = address(0x1234);
        ProxyAdmin proxyAdmin = new ProxyAdmin(deployer);
        // Create a new AgentFactory
        // Initialize with the new base EigenAgent
        IAgentFactory newAgentFactory = IAgentFactory(
            payable(address(
                new TransparentUpgradeableProxy(
                    address(new AgentFactory()),
                    address(proxyAdmin),
                    abi.encodeWithSelector(
                        AgentFactory.initialize.selector,
                        newERC6551Registry,
                        eigenAgentOwner721,
                        newBaseEigenAgent
                    )
                )
            ))
        );

        // Set the RestakingConnector on the AgentFactory
        newAgentFactory.setRestakingConnector(mockRestakingConnector);
        vm.stopPrank();

        // Configure eigenAgentOwner721 to work with the new AgentFactory
        vm.startPrank(deployer);
        eigenAgentOwner721.setAgentFactory(IAgentFactory(address(newAgentFactory)));
        eigenAgentOwner721.addToWhitelistedCallers(mockRestakingConnector);
        vm.stopPrank();

        // spawn an EigenAgent
        address newUser = address(0xABCD);
        vm.startPrank(deployer);

        // valid restaking connector
        IEigenAgent6551 newAgent = newAgentFactory.spawnEigenAgentOnlyOwner(newUser);
        vm.stopPrank();

        // Verify the RestakingConnector was correctly set in the newAgent
        assertEq(
            address(newAgent.restakingConnector()),
            mockRestakingConnector,
            "New agent should have correct RestakingConnector"
        );

        vm.startPrank(deployer);
        vm.expectRevert(abi.encodeWithSelector(
            IEigenAgent6551.RestakingConnectorAlreadyInitialized.selector
        ));
        newAgent.setInitialRestakingConnector(address(0x129381));
        vm.stopPrank();
    }
}
