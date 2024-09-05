// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ScriptUtils} from "../script/ScriptUtils.sol";
import {AdminableMock} from "./mocks/AdminableMock.sol";
import {ERC20Minter} from "../src/ERC20Minter.sol";


contract UtilsTests is Test, ScriptUtils {

    AdminableMock public adminableMock;
    ERC20Minter public erc20Minter;

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);
    address bob = vm.addr(0xb0b);

    function setUp() public {
        vm.startBroadcast(deployer);
        adminableMock = new AdminableMock();
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
        adminableMock.mockOnlyAdmin();

        vm.prank(bob);
        vm.expectRevert("Not admin or owner");
        adminableMock.mockOnlyAdminOrOwner();

        vm.prank(bob);
        require(adminableMock.mockIsOwner() == false, "bob is not owner");

        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        adminableMock.addAdmin(bob);

        vm.prank(deployer);
        adminableMock.addAdmin(bob);

        require(adminableMock.isAdmin(bob), "should be admin");

        vm.prank(bob);
        require(adminableMock.mockOnlyAdmin(), "should pass onlyAdmin modifier");

        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        adminableMock.removeAdmin(bob);

        vm.prank(deployer);
        adminableMock.removeAdmin(bob);

        require(!adminableMock.isAdmin(bob), "should of removed admin");

        vm.prank(deployer);
        require(adminableMock.mockOnlyAdminOrOwner(), "deployer should pass onlyAdminOrOwner modifier");
    }

    function test_ScriptUtils() public {
        // test inherited ScriptUtils vs instantiated ScriptUtils
        ScriptUtils sutils = new ScriptUtils();

        // no gas error
        vm.expectRevert("Failed to send Ether");
        sutils.topupSenderEthBalance(bob, false);

        topupSenderEthBalance(bob, true);
        require(bob.balance == 1 ether, "failed to topupSenderEthBalance");

        // expect balance to stay the same as 0.05 > 0.02 ether
        sutils.topupSenderEthBalance(bob, true);
        require(bob.balance == 1 ether, "oversent ETH in topupSenderEthBalance");
    }

}

