// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IDelegationManager} from "eigenlayer-contracts/src/contracts/interfaces/IDelegationManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IEigenAgent6551} from "../src/6551/IEigenAgent6551.sol";
import {EthSepolia} from "./Addresses.sol";
import {BaseScript} from "./BaseScript.sol";


contract ProcessClaimRewardsScript is BaseScript {

    uint256 deployerKey;
    address deployer;

    address staker;
    address withdrawer;
    uint256 expiry;
    uint256 middlewareTimesIndex; // not used yet, for slashing
    bool receiveAsTokens;

    address TARGET_CONTRACT; // Contract that EigenAgent forwards calls to
    uint256 execNonce; // EigenAgent execution nonce
    IEigenAgent6551 eigenAgent;

    function run() public {
        return _run(false);
    }

    function mockrun() public {
        return _run(true);
    }

    function _run(bool isTest) private {

        deployerKey = vm.envUint("DEPLOYER_KEY");
        deployer = vm.addr(deployerKey);
        readContractsAndSetupEnvironment(isTest, deployer);

        TARGET_CONTRACT = address(delegationManager);

        /////////////////////////////////////////////////////////////////
        ////// L1: Get Complete Withdrawals Params
        /////////////////////////////////////////////////////////////////
        vm.selectFork(ethForkId);

        (
            eigenAgent,
            execNonce
        ) = getEigenAgentAndExecNonce(deployer);

        require(address(eigenAgent) != address(0), "User must have an EigenAgent");

        expiry = block.timestamp + 2 hours;
        staker = address(eigenAgent); // this should be EigenAgent (as in StrategyManager)
        withdrawer = address(eigenAgent);
        // staker == withdrawer == msg.sender in StrategyManager, which is EigenAgent
        require(
            (staker == withdrawer) && (address(eigenAgent) == withdrawer),
            "staker == withdrawer == eigenAgent not satisfied"
        );

    }

}
