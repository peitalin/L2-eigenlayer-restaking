// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {TestErrorHandlers} from "./TestErrorHandlers.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {EigenAgent6551} from "../src/6551/EigenAgent6551.sol";
import {ERC6551Account} from "@6551/examples/simple/ERC6551Account.sol";

import {ERC20Minter} from "./mocks/ERC20Minter.sol";



contract UnitTests_Compare6551Costs is Test, TestErrorHandlers {

    ERC20Minter public erc20Minter;
    ProxyAdmin proxyAdmin;

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    function setUp() public {

        proxyAdmin = new ProxyAdmin();
        // erc20Minter = ERC20Minter(address(
        //     new TransparentUpgradeableProxy(
        //         address(new ERC20Minter()),
        //         address(),
        //         abi.encodeWithSelector(ERC20Minter.initialize.selector, "test", "TST")
        //     )
        // ));
    }

    /*
     *
     *
     *             Tests
     *
     *
     */

    function test_Compare6551Costs() public {

        new EigenAgent6551();

        new ERC6551Account();

        new ERC20Minter();
    }

}

