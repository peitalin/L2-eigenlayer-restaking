// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {DeployOnArbScript} from "../script/2_deployOnArb.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";
import {WhitelistCCIPContractsScript} from "../script/4_whitelistCCIPContracts.s.sol";
import {DepositWithSignatureFromArbToEthScript} from "../script/5_depositWithSignatureFromArbToEth.s.sol";
import {DepositFromArbToEthScript} from "../script/x4_depositFromArbToEth.s.sol";
import {QueueWithdrawalWithSignatureScript} from "../script/6_queueWithdrawalWithSignature.s.sol";
import {CompleteWithdrawalScript} from "../script/7_completeWithdrawal.s.sol";
import {ScriptUtils} from "../script/ScriptUtils.sol";
import {Adminable, MockAdminable} from "../src/utils/Adminable.sol";
import {ERC20Minter} from "../src/ERC20Minter.sol";


contract DeployCCIPScriptsTest is Test, ScriptUtils {

    // deploy scripts
    DeployOnArbScript public deployOnArbScript;
    DeployOnEthScript public deployOnEthScript;
    DepositWithSignatureFromArbToEthScript public depositWithSignatureFromArbToEthScript;
    DepositFromArbToEthScript public depositFromArbToEthScript;
    QueueWithdrawalWithSignatureScript public queueWithdrawalWithSignatureScript;
    CompleteWithdrawalScript public completeWithdrawalScript;
    WhitelistCCIPContractsScript public whitelistCCIPContractsScript;
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

        deployOnArbScript = new DeployOnArbScript();
        deployOnEthScript = new DeployOnEthScript();
        whitelistCCIPContractsScript = new WhitelistCCIPContractsScript();
        depositFromArbToEthScript = new DepositFromArbToEthScript();
        depositWithSignatureFromArbToEthScript = new DepositWithSignatureFromArbToEthScript();
        queueWithdrawalWithSignatureScript = new QueueWithdrawalWithSignatureScript();
        completeWithdrawalScript = new CompleteWithdrawalScript();
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

        vm.prank(deployer);
        mockAdminable.addAdmin(bob);

        require(mockAdminable.isAdmin(bob), "should be admin");

        vm.prank(bob);
        require(mockAdminable.mockOnlyAdmin(), "should pass onlyAdmin modifier");

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
        require(bob.balance == 0.05 ether, "failed to topupSenderEthBalance");

        // expect balance to stay the same as 0.05 > 0.02 ether
        sutils.topupSenderEthBalance(bob);
        require(bob.balance == 0.05 ether, "failed to topupSenderEthBalance");
    }

    function test_step2_DeployOnArbScript() public {
        deployOnArbScript.run();
    }

    function test_step3_DeployOnEthScript() public {
        vm.deal(deployer, 1 ether);
        deployOnEthScript.run();
    }

    function test_step4_WhitelistCCIPContractsScript() public {
        whitelistCCIPContractsScript.run();
    }

    function test_stepx4_DepositFromArbToEthScript() public {
        vm.chainId(31337); // localhost
        depositFromArbToEthScript.run();
    }

    function test_step5_DepositWithSignatureFromArbToEthScript() public {
        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        depositWithSignatureFromArbToEthScript.run();
    }

    // writes new withdrawalRoots
    function test_step6_QueueWithdrawalWithSignatureScript() public {
        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        queueWithdrawalWithSignatureScript.run();
    }

    function test_step7_CompleteWithdrawalScript() public {
        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        completeWithdrawalScript.run();
    }
}

