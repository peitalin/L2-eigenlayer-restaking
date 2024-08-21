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
import {QueueWithdrawalWithSignatureScript} from "../script/7_queueWithdrawalWithSignature.s.sol";
import {CompleteWithdrawalScript} from "../script/8_completeWithdrawal.s.sol";

import {ScriptUtils} from "../script/ScriptUtils.sol";
import {Adminable, MockAdminable} from "../src/utils/Adminable.sol";
import {ERC20Minter} from "../src/ERC20Minter.sol";


contract SenderCCIPTests is Test {

    // deploy scripts
    DeployOnL2Script public deployOnL2Script;
    DeployOnEthScript public deployOnEthScript;
    DepositWithSignatureScript public depositWithSignatureScript;
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

        deployOnL2Script = new DeployOnL2Script();
        deployOnEthScript = new DeployOnEthScript();
        whitelistCCIPContractsScript = new WhitelistCCIPContractsScript();
        depositFromArbToEthScript = new DepositFromArbToEthScript();
        depositWithSignatureScript = new DepositWithSignatureScript();
        queueWithdrawalWithSignatureScript = new QueueWithdrawalWithSignatureScript();
        completeWithdrawalScript = new CompleteWithdrawalScript();
        mockAdminable = new MockAdminable();

        vm.stopBroadcast();
    }

    function test_Sender() public {

    }
}

