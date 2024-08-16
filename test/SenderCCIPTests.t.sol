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


contract SenderCCIPTests is Test {

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

        vm.stopBroadcast();
    }

    function test_Sender() public {

    }
}

