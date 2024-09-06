// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {BaseTestEnvironment} from "./BaseTestEnvironment.t.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IERC6551Executable} from "@6551/interfaces/IERC6551Executable.sol";
import {ERC6551Registry} from "@6551/ERC6551Registry.sol";
import {IERC6551Account, ERC6551Account} from "../src/6551/ERC6551Account.sol";
import {IEigenAgentOwner721} from "../src/6551/IEigenAgentOwner721.sol";


contract ERC6551AccountTest is BaseTestEnvironment {

    ERC6551Registry public registry;
    ERC6551Account public implementation;
    IEigenAgentOwner721 public nft;

    function setUp() public {

        setUpLocalEnvironment();

        registry = new ERC6551Registry();
        implementation = new ERC6551Account();

        nft = agentFactory.eigenAgentOwner721();
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_6551Account_Deploy() public {
        address deployedAccount =
            registry.createAccount(address(implementation), 0, block.chainid, address(0), 0);

        vm.assertTrue(deployedAccount != address(0));

        address predictedAccount =
            registry.account(address(implementation), 0, block.chainid, address(0), 0);

        vm.assertEq(predictedAccount, deployedAccount);
    }

    function test_6551Account_Call() public {

        vm.expectRevert("Ownable: caller is not the owner");
        nft.mintOnlyOwner(bob);

        vm.prank(deployer);
        nft.mintOnlyOwner(bob);

        address account = registry.createAccount(
            address(implementation),
            0,
            block.chainid,
            address(nft),
            1
        );

        vm.assertTrue(account != address(0));

        IERC6551Account accountInstance = IERC6551Account(payable(account));
        IERC6551Executable executableAccountInstance = IERC6551Executable(account);

        vm.assertEq(
            accountInstance.isValidSigner(bob, ""),
            IERC6551Account.isValidSigner.selector
        );

        vm.deal(account, 1 ether);

        vm.prank(bob);

        uint256 aliceBalanceBefore = alice.balance;
        executableAccountInstance.execute(
            payable(alice),
            0.5 ether,
            "",
            0
        );

        vm.assertEq(account.balance, 0.5 ether);
        vm.assertEq(alice.balance, aliceBalanceBefore + 0.5 ether);
        vm.assertEq(accountInstance.execNonce(), 1);
    }

    function test_6551Account_SupportsInterface() public {

        vm.prank(deployer);
        nft.mintOnlyOwner(bob);

        address account = registry.createAccount(
            address(implementation),
            0,
            block.chainid,
            address(nft),
            1
        );

        IERC6551Account accountInstance = IERC6551Account(payable(account));
        IERC6551Executable executableAccountInstance = IERC6551Executable(account);

        accountInstance.supportsInterface(
            type(IERC165).interfaceId
        );
        accountInstance.supportsInterface(
            type(IERC6551Account).interfaceId
        );
    }

}
