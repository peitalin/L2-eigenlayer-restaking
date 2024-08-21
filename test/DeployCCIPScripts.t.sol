// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {DeployOnL2Script} from "../script/2_deployOnL2.s.sol";
import {DeployOnEthScript} from "../script/3_deployOnEth.s.sol";
import {WhitelistCCIPContractsScript} from "../script/4_whitelistCCIPContracts.s.sol";
import {DepositFromArbToEthScript} from "../script/x4_depositFromArbToEth.s.sol";
import {DepositWithSignatureScript} from "../script/5_depositWithSignature.s.sol";
import {DelegateToScript} from "../script/6_delegateTo.s.sol";
import {QueueWithdrawalWithSignatureScript} from "../script/7_queueWithdrawalWithSignature.s.sol";
import {CompleteWithdrawalScript} from "../script/8_completeWithdrawal.s.sol";
import {ScriptUtils} from "../script/ScriptUtils.sol";
import {Adminable, MockAdminable} from "../src/utils/Adminable.sol";
import {ERC20Minter} from "../src/ERC20Minter.sol";


contract DeployCCIPScriptsTest is Test, ScriptUtils {

    // deploy scripts
    DeployOnL2Script public deployOnL2Script;
    DeployOnEthScript public deployOnEthScript;
    WhitelistCCIPContractsScript public whitelistCCIPContractsScript;

    DepositFromArbToEthScript public depositFromArbToEthScript;
    DepositWithSignatureScript public depositWithSignatureScript;

    DelegateToScript public delegateToScript;

    QueueWithdrawalWithSignatureScript public queueWithdrawalWithSignatureScript;
    CompleteWithdrawalScript public completeWithdrawalScript;

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

        deployOnL2Script = new DeployOnL2Script();
        deployOnEthScript = new DeployOnEthScript();
        whitelistCCIPContractsScript = new WhitelistCCIPContractsScript();

        depositFromArbToEthScript = new DepositFromArbToEthScript();
        depositWithSignatureScript = new DepositWithSignatureScript();

        delegateToScript = new DelegateToScript();

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

    function test_step2_DeployOnL2Script() public {
        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        deployOnL2Script.run();
    }

    function test_step3_DeployOnEthScript() public {
        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        vm.deal(deployer, 1 ether);
        deployOnEthScript.run();
    }

    function test_step4_WhitelistCCIPContractsScript() public {
        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        whitelistCCIPContractsScript.run();
    }

    function test_stepx4_DepositScript() public {
        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        depositFromArbToEthScript.run();
    }

    function test_step5_DepositWithSignatureScript() public {
        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        depositWithSignatureScript.run();
    }

    function test_step6_DelegateToScript() public {
        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        vm.deal(deployer, 1 ether);
        delegateToScript.run();
    }

    // writes new withdrawalRoots
    function test_step7_QueueWithdrawalWithSignatureScript() public {
        vm.chainId(31337); // sets isTest flag; script uses forkSelect()
        queueWithdrawalWithSignatureScript.run();
    }

    // function test_step8_CompleteWithdrawalScript() public {
    //     vm.chainId(31337); // sets isTest flag; script uses forkSelect()
    //     completeWithdrawalScript.run();
    // }
}

