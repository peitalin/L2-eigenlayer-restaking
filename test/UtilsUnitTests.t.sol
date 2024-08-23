// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ScriptUtils} from "../script/ScriptUtils.sol";
import {MockAdminable} from "../src/utils/Adminable.sol";
import {ERC20Minter} from "../src/ERC20Minter.sol";


contract UtilsUnitTests is Test, ScriptUtils {

    MockAdminable public mockAdminable;
    ERC20Minter public erc20Minter;

    uint256 public deployerKey;
    address public deployer;
    address public bob;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        bob = vm.addr(0xb0b);

        vm.startBroadcast(deployer);

        mockAdminable = new MockAdminable();
        erc20Minter = ERC20Minter(address(
            new TransparentUpgradeableProxy(
                address(new ERC20Minter()),
                address(new ProxyAdmin()),
                abi.encodeWithSelector(ERC20Minter.initialize.selector, "test", "TST")
            )
        ));

        vm.stopBroadcast();
    }

    function test_ERC20Minter() public {

        vm.expectRevert("Not admin or owner");
        erc20Minter.mint(deployer, 1 ether);

        vm.expectRevert("Ownable: caller is not the owner");
        erc20Minter.burn(deployer, 1 ether);

        vm.prank(deployer);
        erc20Minter.mint(deployer, 1 ether);
        require(erc20Minter.balanceOf(deployer) == 1 ether, "did not mint");

        vm.prank(deployer);
        erc20Minter.burn(deployer, 1 ether);
        require(erc20Minter.balanceOf(deployer) == 0, "did not burn");
    }

    function test_Adminable() public {

        vm.prank(bob);
        vm.expectRevert("Not an admin");
        mockAdminable.mockOnlyAdmin();

        vm.prank(bob);
        vm.expectRevert("Not admin or owner");
        mockAdminable.mockOnlyAdminOrOwner();

        vm.prank(bob);
        require(mockAdminable.mockIsOwner() == false, "bob is not owner");

        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        mockAdminable.addAdmin(bob);

        vm.prank(deployer);
        mockAdminable.addAdmin(bob);

        require(mockAdminable.isAdmin(bob), "should be admin");

        vm.prank(bob);
        require(mockAdminable.mockOnlyAdmin(), "should pass onlyAdmin modifier");

        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        mockAdminable.removeAdmin(bob);

        vm.prank(deployer);
        mockAdminable.removeAdmin(bob);

        require(!mockAdminable.isAdmin(bob), "should of removed admin");

        vm.prank(deployer);
        require(mockAdminable.mockOnlyAdminOrOwner(), "deployer should pass onlyAdminOrOwner modifier");
    }

    function test_ScriptUtils() public {
        // test inherited ScriptUtils vs instantiated ScriptUtils
        ScriptUtils sutils = new ScriptUtils();

        // no gas error
        vm.expectRevert("Failed to send Ether");
        sutils.topupSenderEthBalance(bob);

        topupSenderEthBalance(bob);
        require(bob.balance == sutils.amountToTopup(), "failed to topupSenderEthBalance");

        // expect balance to stay the same as 0.05 > 0.02 ether
        sutils.topupSenderEthBalance(bob);
        require(bob.balance == sutils.amountToTopup(), "failed to topupSenderEthBalance");
    }

}

