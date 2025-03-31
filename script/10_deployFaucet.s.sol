// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TransparentUpgradeableProxy} from "@openzeppelin-v5-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {BaseScript} from "./BaseScript.sol";
import {Faucet} from "../src/utils/faucet.sol";
import {BaseSepolia} from "./Addresses.sol";

contract DeployFaucetScript is BaseScript {

    uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
    address deployer = vm.addr(deployerKey);

    function run() public {
        vm.selectFork(ethForkId);
        vm.startBroadcast(deployerKey);

        // deploy faucet proxy
        Faucet faucet = Faucet(payable(address(
            new TransparentUpgradeableProxy(
                address(new Faucet()),
                address(deployer),
                abi.encodeWithSelector(
                    Faucet.initialize.selector,
                    BaseSepolia.BridgeToken,
                    10 ether
                )
            )
        )));

        vm.stopBroadcast();
    }

    function test_ignore_deploy_faucet() private {}
}

