// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ScriptUtils} from "../script/ScriptUtils.sol";
import {AdminableMock} from "./mocks/AdminableMock.sol";
import {ERC20Minter} from "../src/ERC20Minter.sol";
import {FileReader} from "../script/FileReader.sol";

contract UtilsTests is Test, ScriptUtils {

    AdminableMock public adminableMock;
    ERC20Minter public erc20Minter;
    FileReader public fileReaderTest;

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);
    address bob = vm.addr(0xb0b);

    function setUp() public {

        fileReaderTest = new FileReader();

        vm.startBroadcast(deployer);
        {
            adminableMock = new AdminableMock();
            erc20Minter = ERC20Minter(address(
                new TransparentUpgradeableProxy(
                    address(new ERC20Minter()),
                    address(new ProxyAdmin()),
                    abi.encodeWithSelector(ERC20Minter.initialize.selector, "test", "TST")
                )
            ));
        }
        vm.stopBroadcast();
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_FileReaderFunctions() public {
        fileReaderTest.readAgentFactory();
        fileReaderTest.readEigenAgent721AndRegistry();
        fileReaderTest.readReceiverRestakingConnector();
        fileReaderTest.readProxyAdminL1();
        fileReaderTest.readProxyAdminL2();
        fileReaderTest.readSenderContract();
        fileReaderTest.readSenderHooks();
        fileReaderTest.readWithdrawalInfo(
            address(0x72C14ee915790038af0764d33Bb4B1a63212fC50),
            "script/withdrawals-queued/"
        );
        fileReaderTest.saveReceiverBridgeContracts(
            vm.addr(1),
            vm.addr(2),
            vm.addr(3),
            vm.addr(4),
            vm.addr(5),
            vm.addr(6),
            "test/temp-files/bridgeContractsL1.config.json"
        );
        fileReaderTest.saveSenderBridgeContracts(
            vm.addr(1),
            vm.addr(2),
            vm.addr(3),
            "test/temp-files/bridgeContractsL2.config.json"
        );
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

