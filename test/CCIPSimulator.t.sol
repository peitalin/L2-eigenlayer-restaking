// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IRouterClient, WETH9, LinkToken, BurnMintERC677Helper} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";
import {CCIPLocalSimulator} from "@chainlink/local/src/ccip/CCIPLocalSimulator.sol";

import {DeployMockEigenlayerContractsScript} from "../script/1_deployMockEigenlayerContracts.s.sol";
import {MockERC20} from "../src/MockERC20.sol";


contract CCIPLocalSimulatorTest is Test {

    CCIPLocalSimulator public ccipLocalSimulator;

    uint64 public chainSelector;
    IRouterClient public sourceRouter;
    IRouterClient public destinationRouter;
    WETH9 public wrappedNative;
    LinkToken public linkToken;
    BurnMintERC677Helper public ccipBnM;
    BurnMintERC677Helper public ccipLnM;

    DeployMockEigenlayerContractsScript public deployMockEigenlayerContractsScript;

    uint256 public deployerKey;
    address public deployer;

    function setUp() public {

		deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);

        ccipLocalSimulator = new CCIPLocalSimulator();

        (
            chainSelector,
            sourceRouter,
            destinationRouter,
            wrappedNative,
            linkToken,
            ccipBnM,
            ccipLnM
        ) = ccipLocalSimulator.configuration();

        deployMockEigenlayerContractsScript = new DeployMockEigenlayerContractsScript();
    }

    function test_CCIPConfigurationInitialized() public {

        ccipLocalSimulator.requestLinkFromFaucet(deployer, 1.25e18);
        uint256 balance = linkToken.balanceOf(deployer);
        console.log("ccipLocalSimulator.requestLinkFromFaucet(balance): ", balance);

        ProxyAdmin proxyAdmin = deployMockEigenlayerContractsScript.deployProxyAdmin();

        MockERC20 mockERC20 = deployMockEigenlayerContractsScript.deployMockERC20(
            "Mock Magic",
            "MMAGIC",
            proxyAdmin
        );

        ccipLocalSimulator.supportNewToken(address(mockERC20));

        address[] memory supportedTokens = ccipLocalSimulator.getSupportedTokens(chainSelector);

        bool supportsMockERC20 = false;
        for (uint32 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == address(mockERC20)) {
                console.log("supports MockERC20: ", supportedTokens[i]);
                supportsMockERC20 = true;
            }
        }

        require(balance == 1.25e18, "balance not matching");
        require(supportsMockERC20, "ccip should support new MockERC20");
    }

}
