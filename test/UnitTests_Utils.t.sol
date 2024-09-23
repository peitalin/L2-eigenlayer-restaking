// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {TestErrorHandlers} from "./TestErrorHandlers.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IStrategy} from "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";

import {BytesLib} from "../src/utils/BytesLib.sol";
import {BaseScript} from "../script/BaseScript.sol";
import {AdminableMock} from "./mocks/AdminableMock.sol";
import {ERC20Minter} from "./mocks/ERC20Minter.sol";
import {FileReader} from "../script/FileReader.sol";


contract UnitTests_Utils is Test, TestErrorHandlers {

    AdminableMock public adminableMock;
    ERC20Minter public erc20Minter;
    FileReader public fileReaderTest;
    BaseScript public baseScript;

    address bob = vm.addr(0xb0b);
    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

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

    function test_FileReader_ReadContracts() public {
        fileReaderTest.readAgentFactory();
        fileReaderTest.readEigenAgent721AndRegistry();
        fileReaderTest.readBaseEigenAgent();
        fileReaderTest.readReceiverRestakingConnector();
        fileReaderTest.readProxyAdminL1();
        fileReaderTest.readProxyAdminL2();
        fileReaderTest.readSenderContract();
        fileReaderTest.readSenderHooks();
        fileReaderTest.saveReceiverBridgeContracts(
            vm.addr(1),
            vm.addr(2),
            vm.addr(3),
            vm.addr(4),
            vm.addr(5),
            vm.addr(6),
            vm.addr(7),
            "test/temp-files/bridgeContractsL1.config.json"
        );
        fileReaderTest.saveSenderBridgeContracts(
            vm.addr(1),
            vm.addr(2),
            vm.addr(3),
            "test/temp-files/bridgeContractsL2.config.json"
        );
    }

    function test_FileReader_ReadAndWriteWithdrawals() public {

        uint256[] memory shares = new uint256[](1);
        IStrategy[] memory strategies = new IStrategy[](1);
        shares[0] = 200;
        strategies[0] = IStrategy(address(123123));

        fileReaderTest.saveWithdrawalInfo(
            0x0000000000000000000000000000000000000001, // _staker
            0x0000000000000000000000000000000000000002, // _delegatedTo
            0x0000000000000000000000000000000000000003, // , _withdrawer
            5, // _nonce
            100, // _startBlock
            strategies, // _strategies
            shares, // _shares
            bytes32(0x0), // _withdrawalRoot
            bytes32(0x0), // _withdrawalTransferRoot
            "test/withdrawals-queued/" // _filePath
        );

        IDelegationManager.Withdrawal memory wt = fileReaderTest.readWithdrawalInfo(
            address(0x0000000000000000000000000000000000000001),
            "test/withdrawals-queued/"
        );

        vm.assertEq(wt.staker, 0x0000000000000000000000000000000000000001);
        vm.assertEq(wt.delegatedTo, 0x0000000000000000000000000000000000000002);
        vm.assertEq(wt.withdrawer, 0x0000000000000000000000000000000000000003);
        vm.assertEq(wt.nonce, 5);
        vm.assertEq(wt.startBlock, 100);
        vm.assertEq(address(wt.strategies[0]), address(strategies[0]));
        vm.assertEq(wt.shares[0], shares[0]);
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

    function test_BytesLib_Slices() public {

        bytes memory bstring = hex"";
        bytes memory newBstring = BytesLib.slice(bstring, 0, 0);

        vm.assertEq(newBstring, hex"");

        bytes memory bstring2 = hex"123456789a";
        vm.assertEq(BytesLib.slice(bstring2, 1, 3), hex"345678");

        vm.assertEq("4Vx", string(hex"345678"));

        bytes memory bstring3 = hex"123456789abcdef0";
        vm.expectRevert("slice_outOfBounds");
        BytesLib.slice(bstring3, 10, 1000);

    }

    function test_BaseScript_TopupEthBalance() public {

        // Test inherited BaseScript vs instantiated BaseScript for test coverage
        // msg.sender is sutils in this case.
        BaseScript sutils = new BaseScript();

        // no gas error
        vm.expectRevert("Failed to send Ether");
        sutils.topupEthBalance(bob);

        // give sutils some ether
        vm.deal(address(sutils), 2 ether);
        sutils.topupEthBalance(bob);
        require(bob.balance > 0, "failed to topupEthBalance");

        uint256 bobBalanceBefore = bob.balance;

        // expect balance to stay the same as 0.05 > 0.02 ether
        sutils.topupEthBalance(bob);
        require(bob.balance == bobBalanceBefore , "oversent ETH in topupEthBalance");
    }

}

